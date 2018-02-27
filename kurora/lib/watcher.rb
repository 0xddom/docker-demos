require 'queue'

class WatcherMode
  attr_reader :queue
  attr_accessor :boards
  attr_accessor :threads
  
  def initialize(args)
    @queue = RestQueue.new
    # Only scrap these boards
    @boards = {
     # b: {
     #   threads: {}
     # },
      pol: {
        threads: {}
      },
     # a: {
     #   threads: {}
     # },
     # g: {
     #   threads: {}
     # }
    }
    @threads = {}
    @update_boards_timeout = 5
  end

  def run
    @queue.enqueue Queues.crawling_requests, 'boards'
    each 0.2 do
      #get_boards
      prune_threads
      send_update_board_threads
      get_threads
      update_threads
    end
  end

  def update_threads
    @boards.each do |name, board|
      board[:threads].each do |thread_no, thread|
        thread[:timeout] -= 1
        if thread[:timeout] == 0
          thread[:timeout] = 100
          @queue.enqueue Queues.crawling_requests, "thread,#{name},#{thread_no}"
        end
      end
    end
  end

  def prune_threads
    while thread = @queue.dequeue(Queues.pruned_threads)
      
      board, thread_no = thread['value'].slice ','
      if @boards.has_key? board.to_s.to_sym
        @boards[board.to_s.to_sym][:threads].delete thread_no.to_sym
      end
    end
  end
  
  def send_update_board_threads
    if @update_boards_timeout == 0
      @boards.each do |name, board|
        @queue.enqueue Queues.crawling_requests, "threads,#{name}"
      end
      @update_boards_timeout = 300
    else
      @update_boards_timeout -= 1
    end
  end
  
  def get_boards
    board_resp = @queue.dequeue Queues.boards
    #p board_resp
    unless board_resp.nil?
      board = board_resp['value']
      unless @boards.has_key? board
        @boards[board.to_s.to_sym] = {
          threads: {}
        }
      end
    end
  end

  def get_threads
    thread_resp = @queue.dequeue Queues.threads
    #p thread_resp
    unless thread_resp.nil?
      thread = thread_resp['value'].split ','
      board = thread[0]
      thread_no = thread[1]

      #p @boards
      if @boards.has_key? board.to_s.to_sym
        board_threads = @boards[board.to_s.to_sym][:threads]
        unless board_threads.has_key? thread_no
          board_threads[thread_no.to_s.to_sym] = {
            timeout: 100
          }
        end
      end
    end
  end
  
  def each(n)
    while true
      yield
      sleep n
    end
  end
end
