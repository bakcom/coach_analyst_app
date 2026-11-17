require "json"

module CoachAnalyst
  # Small filesystem helpers for cache persistence (mirrors storage.py).
  module Storage
    module_function

    # Write JSON via a temp file + rename so readers never see a partial file.
    def write_json_atomic(path, data)
      path = Pathname.new(path)
      path.dirname.mkpath
      tmp = path.dirname.join("#{path.basename}.tmp")
      tmp.write(JSON.generate(data))
      File.rename(tmp, path)
    end

    def read_json(path)
      JSON.parse(Pathname.new(path).read)
    rescue Errno::ENOENT, JSON::ParserError
      nil
    end
  end
end
