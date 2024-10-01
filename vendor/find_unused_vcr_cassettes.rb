require 'find'

# Directory where your test files are located
test_dir = '../test'

# Directory where your VCR cassettes are stored
cassette_dir = '../fixtures/vcr_cassettes'

# Find all test files
test_files = Find.find(test_dir).select { |path| path =~ /\_test\.rb$/ }

# Find all VCR cassettes
cassettes = Dir.glob("#{cassette_dir}/**/*.yml")

# Extract cassette names from test files
used_cassettes = []
test_files.each do |file|
  File.readlines(file).each do |line|
    if line =~ /VCR\.use_cassette\(['"](.+?)['"]/
      used_cassettes << $1
    end
  end
end

# Find unused cassettes
unused_cassettes = cassettes.reject do |cassette|
  used_cassettes.any? { |used| cassette.include?(used) }
end

# Print unused cassettes
if unused_cassettes.empty?
  puts "No unused VCR cassettes found."
else
  puts "Unused VCR cassettes:"
  unused_cassettes.each do |cassette|
    puts cassette
    # Uncomment the next line to delete unused cassettes
    # File.delete(cassette)
  end
end
