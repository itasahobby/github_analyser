require "HTTParty"
require "Nokogiri"
require "optparse"
require "json"

class Scraper
    def scrape_repositories(html)
        repositories = Array.new
        parser = Nokogiri::HTML(html)
        # añadir que no incluya githubs forkeds
        parser.xpath("//ul[@data-filterable-for='your-repos-filter']/li/div/div/h3/a/@href").map{|repository| repositories.push(repository.value)}
        return repositories
    end

    def scrape_branches(html)
        branches = Array.new
        parser = Nokogiri::HTML(html)
        parser.xpath("//a[@class='branch-name css-truncate-target v-align-baseline width-fit mr-2 Details-content--shown']/@href").map{|branch| branches.push(branch.value)}
        return branches
    end

    def scrape_commits_link(html)
        parser = Nokogiri::HTML(html)
        commit_url = parser.xpath("//li[@class='commits']/a/@href").first.value
        return commit_url
    end

    def scrape_all_commits(html)
        commits = Array.new
        parser = Nokogiri::HTML(html)
        parser.xpath("//div[@class='commit-links-group BtnGroup']/a/@href").map{|commit| commits.push(commit.value)}
        return commits
    end
end

class Requester

    def initialize()
        @base_url = "https://github.com/"
    end

    def get_api_content(user)
        url = "https://api.github.com/users/#{user}/events/public"
        response = HTTParty.get(url)
        body = JSON.parse(response.body)
        return body
    end

    def get_repositories(user)
        url = "#{@base_url}#{user}?tab=repositories"
        response = HTTParty.get(url)
        body = response.body
        return body
    end

    def get_branches(repository)
        url = "#{@base_url}#{repository}/branches"
        response = HTTParty.get(url)
        body = response.body
        return body
    end

    def get_commits(branch)
        url = "#{@base_url}#{branch}"
        response = HTTParty.get(url)
        body = response.body
        return body
    end

    def get_commit_data(commit)
        url = "#{@base_url}#{commit}.patch"
        response = HTTParty.get(url)
        body = response.body
        return body
    end
end

class Searcher
    def search_api_emails(content)
        emails = Array.new
        # Iterates through events
        content.each do |event|
            payload = event["payload"]
            commits = payload["commits"]
            # Some events have no commit assigned
            unless commits.nil?
                commits.each do |commit|
                    emails.push(commit["author"]["email"])
                end
            end
        end
        return emails.uniq
    end

    def search_sensitive_info(commit)
        data = Hash.new
        data["mails"] = commit[/[<]{0,1}[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}[>]{0,1}/]
        return data
    end
end

class Parser
    def self.parse(args)
        options = {
            "output_file" => "github_analysis.json" 
        }
        opts = OptionParser.new{ |opts|
            opts.banner = "Usage: github_analyzer.rb [options]"

            opts.on("-uUSERNAME", "--username=USERNAME", "Github username to analyze"){ |n |
                options["username"] = n
            }

            opts.on("-oOUTPUT", "--output-file=OUTPUT", "Json file to store the analysis"){ |n |
                options["output_file"] = n
            }

            opts.on("-h", "--help", "Prints this help"){
                options["help"] = true
                puts opts
                exit
            }

        }
        opts.parse(args)
        if options.empty?  
            puts opts
        elsif options["username"].nil? and !options["help"]
            raise OptionParser::MissingArgument
        end
        options
    end
end

class App
    def initialize()
        @req = Requester.new
        @scr = Scraper.new
        @sear = Searcher.new
        @options = Parser.parse(ARGV)
    end
    def run 
        api_content = @req.get_api_content(@options["username"])
        account_email = @sear.search_api_emails(api_content)
        repositories = Array.new
        @scr.scrape_repositories(@req.get_repositories(@options["username"])).map{ |repository|
            data = Hash.new
            data["id"] = repository
            repositories.push(data)
        }
        repositories.each{ |repository|
            repository["branches"] = Array.new
            @scr.scrape_branches(@req.get_branches(repository["id"])).each{ |branch|
                data = Hash.new 
                data["id"] = branch
                commits_url = @scr.scrape_commits_link(@req.get_commits(branch))
                data["commits_url"] = commits_url
                repository["branches"].push(data)
                src = Scraper.new
                commits = src.scrape_all_commits(@req.get_commits(commits_url))
                data["commits"] = Array.new
                commits.each{ |commit|
                    commit_obj = Hash.new
                    commit_obj["commit"] = commit
                    commit_obj["info"] = @sear.search_sensitive_info(@req.get_commit_data(commit))
                    data["commits"].push commit_obj
                }
            }
        }
        File.open(@options["output_file"], "w") { |f| f.write repositories.to_json }
    end
end

app = App.new
app.run()