require 'httparty'

class FourChan
  include HTTParty
  base_uri 'a.4cdn.org'

  def boards
    self.class.get('/boards.json').parsed_response
  end

  def threads(board)
    self.class.get("/#{board}/threads.json").parsed_response
  end

  def thread(board, thread)
    self.class.get("/#{board}/thread/#{thread}.json").parsed_response
  end
end
