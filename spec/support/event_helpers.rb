module EventHelpers
  def mock_event(event, params)
    expect(Jellyswitch::Events).to receive(:publish).once.with(event, params)
  end
end
