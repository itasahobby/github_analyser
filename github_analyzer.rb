require "HTTParty"
require "Nokogiri"
require "optparse"
require "json"
require "colorize"

class RepoNotFound < StandardError
    def initialize()
        msg="The given repository doesn't exist".blue
        super(msg)
    end
end

class Scraper
    def scrape_repositories(html,deep)
        repositories = Array.new
        parser = Nokogiri::HTML(html)
        # añadir que no incluya githubs forkeds
        if deep
            parser.xpath("//ul[@data-filterable-for='your-repos-filter']/li/div/div/h3/a/@href").map{|repository| repositories.push(repository.value)}
        else 
            parser.xpath("//ul[@data-filterable-for='your-repos-filter']/li/div/div[@class='d-inline-block mb-1'][not(./span[contains(.,'Forked from')])]//@href").map{|repository| repositories.push(repository.value)}
        end
        return repositories
    end

    def scrape_branches(html)
        branches = Array.new
        parser = Nokogiri::HTML(html)
        parser.xpath("//a[@class='branch-name css-truncate-target v-align-baseline width-fit mr-2 Details-content--shown']/@href").map{|branch| branches.push(branch.value)}
        if branches.empty?
            raise RepoNotFound
        end
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

class UserNotFound < StandardError
    def initialize()
        msg="The given username doesn't exist".blue
        super(msg)
    end
end

class Searcher
    def search_api_emails(content)
        emails = Array.new
        if content.is_a? Hash
            raise UserNotFound
        end
        # Iterates through events
        content.each do |event|
            payload = event["payload"]
            commits = payload["commits"]
            # Some events have no commit assigned
            unless commits.nil?
                commits.each do |commit|
                    if(!commit["author"]["email"][/[<]{0,1}[a-zA-Z0-9._%+-]+@users.noreply.github.com[>]{0,1}/])
                        emails.push(commit["author"]["email"])
                    end
                end
            end
        end
        return emails.uniq
    end

    def search_sensitive_info(commit)
        data = Hash.new
        data["email"] = commit[/[<]{0,1}[a-zA-Z0-9._%+-]+@(?![users\.noreply\.]{0,1}github\.com)([a-zA-Z0-9.-]+\.[a-zA-Z]{2,4})[>]{0,1}/]
        return data
    end
end

class ArgParser
    def self.parse(args)
        options = {
            "output_file" => "github_analysis.json",
            "unique" => false,
            "forked" => true
        }
        opts = OptionParser.new{ |opts|
            opts.banner = "Usage: github_analyzer.rb [options]"

            opts.on("-uUSERNAME", "--username=USERNAME", "Github username to analyze"){ |n |
                options["username"] = n
            }

            opts.on("-oOUTPUT", "--output-file=OUTPUT", "Json file to store the analysis"){ |n |
                options["output_file"] = n
            }

            opts.on("-U", "--unique", "Only shows first appearance of each email"){ |n |
                options["unique"] = true
            }

            opts.on("-F","--non-forked","If used only analyzes non forked repositories"){ |n|
                options["forked"] = false
            }

            opts.on("-rREPO","--repositoryREPO","Analyze only the given repository"){ |n|
                options["repository"] = n
            }

            opts.on("-h", "--help", "Prints this help"){
                options["help"] = true
                puts opts
                exit
            }

        }
        opts.parse(args)
        if options["username"].nil? and !options["help"]
            puts "There is no help"
            raise OptionParser::MissingArgument
        end
        options
    end
end

class Printer
    def print_banner()
        banner = File.read('banner.txt')
        puts banner.yellow
    end
    
    def print_result(result)
        acc_email_header = "Account emails: ".yellow
        commit_email_header = "Emails found on commits".yellow
        
        puts acc_email_header
        result["account_email"].each{ |email|
            puts "\t[·] ".yellow + email.red
        }.first.red
        
        puts commit_email_header
        result["repositories"].each{ |repository|
            repository["branches"].each{ |branch|
                branch["commits"].each{ |commit|
                    if(!commit["info"]["email"].nil?)
                        puts "\t[·] ".yellow + commit["info"]["email"].red + " found in " + 
                        "#{repository["id"]}".green + " inside branch " + "#{branch["id"][/\/[a-zA-Z0-9]*$/]}".green +
                        " and commit " + "#{commit["commit"][/\/[a-zA-Z0-9]*$/]}".green
                    end
                }
            }
        }

    end

end

class App
    def initialize()
        @req = Requester.new
        @scr = Scraper.new
        @sear = Searcher.new
        @options = ArgParser.parse(ARGV)
        @print = Printer.new
    end
    def run 
        @print.print_banner()
        api_content = @req.get_api_content(@options["username"])
        account_email = @sear.search_api_emails(api_content)
        repositories = Array.new
        if @options["repository"]
            repositories.push({
                "id" => "/#{@options["username"]}/#{@options["repository"]}"
            })
        else
            @scr.scrape_repositories(@req.get_repositories(@options["username"]), @options["forked"]).map{ |repository|
                data = Hash.new
                data["id"] = repository
                repositories.push(data)
            }
        end
        unique_mails = Array.new
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
                    info = @sear.search_sensitive_info(@req.get_commit_data(commit))
                    if(@options["unique"] and !unique_mails.include? info["email"])
                        commit_obj["commit"] = commit
                        commit_obj["info"] = info
                        data["commits"].push commit_obj
                        unique_mails.push info["email"]
                    end
                }
            }
        }
        result = {
            "account_email" => account_email,
            "repositories"  => repositories 
        }
        File.open(@options["output_file"], "w") { |f| f.write result.to_json }
        @print.print_result(result)
    end
end

app = App.new
app.run()