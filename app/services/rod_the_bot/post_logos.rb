require "timeout"
require "tmpdir"

module RodTheBot
  class PostLogos
    class Error < StandardError; end

    def self.with_images(urls)
      Dir.mktmpdir("post-logos-") do |directory|
        images = []
        begin
          urls.each_with_index do |url, index|
            response = HTTParty.get(url, timeout: 10)
            raise Error, "Logo download failed for #{url}: HTTP #{response.code}" unless response.success?

            svg_path = File.join(directory, "#{index}.svg")
            png_path = File.join(directory, "#{index}.png")
            File.binwrite(svg_path, response.body)
            render(svg_path, png_path, url)
            images << File.open(png_path, "rb")
          end
          yield images
        ensure
          images.each(&:close)
        end
      end
    end

    def self.render(svg_path, png_path, url)
      pid = Process.spawn("rsvg-convert", "--background-color", "white", "--height", "600", "--output", png_path, svg_path, out: File::NULL, err: File::NULL)
      status = nil
      begin
        Timeout.timeout(15) { _, status = Process.wait2(pid) }
      rescue Timeout::Error
        Process.kill("KILL", pid)
        Process.wait(pid)
        raise Error, "Logo rendering timed out for #{url}"
      end
      raise Error, "Logo rendering failed for #{url}" unless status.success?
    end
    private_class_method :render
  end
end
