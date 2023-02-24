# difference between production and staging environments

# Staging uses Bonsai add-on
ENV["OPENSEARCH_URL"] = ENV["BONSAI_URL"] || ENV["BONSAI_GREEN_URL"]
