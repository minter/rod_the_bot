module RodTheBot
  class PostThread
    CHARACTER_LIMIT = 300
    DEFAULT_DELAY = 30.seconds

    def self.enqueue(chunks, key:, delay: DEFAULT_DELAY)
      chunks = chunks.compact_blank
      return if chunks.empty?
      return Post.perform_async(chunks.first) if chunks.one?

      first_key = "#{key}:1"
      Post.perform_async(chunks.first, first_key)
      chunks.drop(1).each_with_index do |chunk, index|
        number = index + 2
        Post.perform_in(index.next * delay, chunk, "#{key}:#{number}", "#{key}:#{number - 1}")
      end
    end

    def self.split(text, limit: content_limit)
      pieces = text.split(/\n{2,}/).flat_map { |paragraph| split_paragraph(paragraph, limit) }
      pieces.each_with_object([]) do |piece, chunks|
        candidate = [chunks.last, piece].compact.join("\n\n")
        if chunks.any? && candidate.length <= limit
          chunks[-1] = candidate
        else
          chunks << piece
        end
      end
    end

    def self.split_lines(lines, header: nil, limit: content_limit)
      chunks = []
      current = +header.to_s
      lines.each do |line|
        if current.present? && current.length + line.length > limit
          chunks << current
          current = +""
        end
        current << line
      end
      chunks << current if current.present?
      chunks
    end

    def self.content_limit
      hashtags = ENV["TEAM_HASHTAGS"].to_s
      CHARACTER_LIMIT - (hashtags.empty? ? 0 : hashtags.length + 1)
    end

    def self.split_paragraph(paragraph, limit)
      return [paragraph] if paragraph.length <= limit

      paragraph.each_line(chomp: true).flat_map { |line| wrap_line(line, limit) }
    end
    private_class_method :split_paragraph

    def self.wrap_line(line, limit)
      line.split.each_with_object([]) do |word, chunks|
        candidate = [chunks.last, word].compact.join(" ")
        if chunks.any? && candidate.length <= limit
          chunks[-1] = candidate
        else
          chunks << word
        end
      end
    end
    private_class_method :wrap_line
  end
end
