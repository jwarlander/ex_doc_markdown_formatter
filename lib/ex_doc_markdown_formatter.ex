defmodule ExDocMarkdownFormatter do
  @moduledoc """
  Generates Markdown documentation for Elixir projects.
  """

  alias __MODULE__.{Autolink, Templates}
  alias ExDoc.GroupMatcher

  @doc """
  Generate Markdown documentation for the given modules.
  """
  @spec run(list, ExDoc.Config.t()) :: String.t()
  def run(project_nodes, config) when is_map(config) do
    config = %{config | output: Path.expand(config.output)}

    build = Path.join(config.output, ".build")
    output_setup(build, config)

    autolink = Autolink.compile(project_nodes, ".html", config.deps)
    linked = Autolink.all(project_nodes, autolink)

    nodes_map = %{
      modules: filter_list(:module, linked),
      exceptions: filter_list(:exception, linked),
      tasks: filter_list(:task, linked)
    }

    extras = build_extras(config, autolink)

    generated_files =
      generate_extras(nodes_map, extras, config) ++
        generate_list(nodes_map.modules, nodes_map, config) ++
        generate_list(nodes_map.exceptions, nodes_map, config) ++
        generate_list(nodes_map.tasks, nodes_map, config)

    generate_build(generated_files, build)
    config.output |> Path.relative_to_cwd()
  end

  defp output_setup(build, config) do
    if File.exists?(build) do
      build
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&Path.join(config.output, &1))
      |> Enum.each(&File.rm/1)

      File.rm(build)
    else
      File.rm_rf!(config.output)
      File.mkdir_p!(config.output)
    end
  end

  defp generate_build(files, build) do
    entries = Enum.map(files, &[&1, "\n"])
    File.write!(build, entries)
  end

  defp generate_extras(_nodes_map, extras, config) do
    Enum.map(extras, fn %{id: id, content: content} ->
      filename = "#{id}.md"
      output = "#{config.output}/#{filename}"

      if File.regular?(output) do
        IO.puts(:stderr, "warning: file #{Path.relative_to_cwd(output)} already exists")
      end

      File.write!(output, content)
      filename
    end)
  end

  @doc """
  Builds extra nodes by normalizing the config entries.
  """
  def build_extras(config, autolink) do
    groups = config.groups_for_extras

    config.extras
    |> Task.async_stream(&build_extra(&1, autolink, groups), timeout: :infinity)
    |> Enum.map(&elem(&1, 1))
    |> Enum.sort_by(fn extra -> GroupMatcher.group_index(groups, extra.group) end)
  end

  defp build_extra({input, options}, autolink, groups) do
    input = to_string(input)
    id = options[:filename] || input |> input_to_title() |> title_to_id()
    build_extra(input, id, options[:title], autolink, groups)
  end

  defp build_extra(input, autolink, groups) do
    id = input |> input_to_title() |> title_to_id()
    build_extra(input, id, nil, autolink, groups)
  end

  defp build_extra(input, id, title, autolink, groups) do
    if valid_extension_name?(input) do
      content =
        input
        |> File.read!()
        |> Autolink.project_doc(autolink)

      group = GroupMatcher.match_extra(groups, input)

      title = title || extract_title(content) || input_to_title(input)
      %{id: id, title: title, group: group, content: content}
    else
      raise ArgumentError, "file format not recognized, allowed format is: .md"
    end
  end

  def valid_extension_name?(input) do
    file_ext =
      input
      |> Path.extname()
      |> String.downcase()

    if file_ext in [".md"] do
      true
    else
      false
    end
  end

  @h1_regex ~r/^#\s+(.+)\s+$/m
  defp extract_title(content) do
    title = Regex.run(@h1_regex, content, capture: :all_but_first)

    if title do
      title |> List.first() |> String.trim()
    end
  end

  @doc """
  Convert the input file name into a title_to_filename/1
  """
  def input_to_title(input) do
    input |> Path.basename() |> Path.rootname()
  end

  @doc """
  Creates an ID from a given title
  """
  def title_to_id(title) do
    title |> String.replace(" ", "-") |> String.downcase()
  end

  def filter_list(:module, nodes) do
    Enum.filter(nodes, &(not (&1.type in [:exception, :impl, :task])))
  end

  def filter_list(type, nodes) do
    Enum.filter(nodes, &(&1.type == type))
  end

  defp generate_list(nodes, nodes_map, config) do
    nodes
    |> Task.async_stream(&generate_module_page(&1, nodes_map, config), timeout: :infinity)
    |> Enum.map(&elem(&1, 1))
  end

  defp generate_module_page(module_node, nodes_map, config) do
    filename = "#{module_node.id}.md"
    config = set_canonical_url(config, filename)
    content = Templates.module_page(module_node, nodes_map, config)
    File.write!("#{config.output}/#{filename}", content)
    filename
  end

  defp set_canonical_url(config, filename) do
    if config.canonical do
      canonical_url =
        config.canonical
        |> String.trim_trailing("/")
        |> Path.join(filename)

      Map.put(config, :canonical, canonical_url)
    else
      config
    end
  end
end
