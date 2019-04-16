module SystemHelpers
  def start_session(name, user_session, &block)
    using_session(name) do
      yield(user_session)
    end
  end
end
