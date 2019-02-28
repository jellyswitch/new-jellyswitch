module Demo::Avatars
  def avatar_ids
    [0,1,2,3,4,5,6,7,8,14,15,21,24,27,37,42,44,57,60,61,71,72,77,79,81].map do |num|
      "#{num}.jpg"
    end
  end
end