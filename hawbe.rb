require 'yaml'

def nodes()
  result = {
    :sources => [],
    :bosh_releases => [],
    :binaries => [],
    :images => [],
    :charts => [],
    :tarballs => [],
    :docs => [],
    :pipelines => [],
    :groups => {},
  }

  # load YAMLs from disk
  graph_dir = File.join(File.dirname(__FILE__), "graph")

  # Get all yamls from the directory
  yaml_files = Dir[File.join(graph_dir, "*.yaml")]

  yaml_files.each do |file|
    node_list = YAML.load_file(file)

    result[:sources] += node_list["sources"] || []
    result[:bosh_releases] += node_list["bosh_releases"] || []
    result[:binaries] += node_list["binaries"] || []
    result[:images] += node_list["images"] || []
    result[:charts] += node_list["charts"] || []
    result[:tarballs] += node_list["tarballs"] || []
    result[:docs] += node_list["docs"] || []
    result[:pipelines] += node_list["pipelines"] || []

    group = File.basename(file, File.extname(file))

    result[:groups][group] = node_list["connections"] || {}
  end

  result
end
