require "find"
require "pathname"

root = Pathname.new(__dir__).join("..").expand_path
test_dir = root.join("test")
cassette_dir = root.join("fixtures/vcr_cassettes")

test_files = Find.find(test_dir).select { |path| path.end_with?("_test.rb") }
cassettes = Dir.glob(cassette_dir.join("**/*.yml"))

# Extract cassette names from test files
used_cassette_patterns = []
test_files.each do |file|
  File.readlines(file).each do |line|
    if line =~ /VCR\.use_cassette\(\s*(["'])(.*)\1(?:\s*,|\s*\))/
      pattern = Regexp.escape(Regexp.last_match(2)).gsub(/\\#\\\{.*?\\\}/, ".+")
      used_cassette_patterns << /\A#{pattern}\.yml\z/
    end
  end
end

# Find unused cassettes
unused_cassettes = cassettes.reject do |cassette|
  relative_path = Pathname.new(cassette).relative_path_from(cassette_dir).to_s
  used_cassette_patterns.any? { |pattern| pattern.match?(relative_path) }
end

# Print unused cassettes
if unused_cassettes.empty?
  puts "No unused VCR cassettes found."
else
  puts "Unused VCR cassettes:"
  unused_cassettes.each do |cassette|
    puts Pathname.new(cassette).relative_path_from(root)
  end
end
