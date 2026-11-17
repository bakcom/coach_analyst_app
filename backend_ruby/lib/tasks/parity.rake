require "json"
require Rails.root.join("parity/ruby_runner").to_s

namespace :parity do
  desc "Compare the Ruby port against the Python backend on synthetic fixtures"
  task run: :environment do
    fixtures_py = Rails.root.join("parity/fixtures.py")
    runner_py = Rails.root.join("parity/run_python.py")
    out_dir = Rails.root.join("tmp/parity")
    out_dir.mkpath

    fixtures = out_dir.join("fixtures.json")
    python_out = out_dir.join("python.json")
    ruby_out = out_dir.join("ruby.json")

    run!(["python3", fixtures_py.to_s, "-o", fixtures.to_s])
    run!(["python3", runner_py.to_s, fixtures.to_s, "-o", python_out.to_s])

    data = JSON.parse(fixtures.read)
    result = Parity::RubyRunner.compute(data)
    ruby_out.write(JSON.pretty_generate(result))

    python = JSON.parse(python_out.read)
    diffs = Parity::Compare.diffs(python, result)

    if diffs.empty?
      puts "PARITY OK — python and ruby agree on all computed values."
    else
      puts "PARITY FAILED — #{diffs.length} difference(s):"
      diffs.first(200).each { |line| puts "  #{line}" }
      exit 1
    end
  end
end

def run!(command)
  puts "$ #{command.join(' ')}"
  raise "command failed: #{command.join(' ')}" unless system(*command)
end
