module RodTheBot
  module GameVideo
    class PostFormatter
      def format(video)
        date = video.date.strftime("%B %-d, %Y")
        "🎥 #{video.label}: #{video.away_name} at #{video.home_name} on #{date}."
      end
    end
  end
end
