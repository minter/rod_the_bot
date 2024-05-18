module Seasons
  def current_season
    HTTParty.get("https://api-web.nhle.com/v1/season").last
  end

  def postseason?
    season = current_season
    HTTParty.get("https://api-web.nhle.com/v1/playoff-series/carousel/#{season}/")["rounds"].present?
  end
end
