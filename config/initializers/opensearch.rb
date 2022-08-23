# difference between production and staging environments

# Staging uses Bonsai add-on
ENV["OPENSEARCH_URL"] = ENV["BONSAI_URL"] if ENV["BONSAI_URL"]
