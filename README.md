# Github Analyzer 🔎

This tool analyzes a github account or repository, looking for sensitive data. Currently only supports emails. The syntaxis is the following:
```
Usage: github_analyzer.rb [-h] [-o ouput_file] [-U] [-F] [-r repository] -u username
    -h, --help                       Prints this help
    -o, --output-file=OUTPUT         Json file to store the analysis
    -U, --unique                     Only shows first appearance of each email
    -F, --non-forked                 If used only analyzes non forked repositories
    -r, --repositoryREPOREPO         Analyze only the given repository
    -u, --username=USERNAME          Github username to analyze
```