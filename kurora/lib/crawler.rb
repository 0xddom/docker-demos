require 'fourchan'
require 'queue'
require 'graph'

class CrawlerMode
  attr_reader :fourchan
  attr_reader :queue
  attr_reader :neo4j
  
  def initialize(args)
    @fourchan = FourChan.new
    @queue = RestQueue.new
    @neo4j = Neo4jAdaptor.new
    @sleep = 1
  end

  def run    
    restmq_queue = Queues.crawling_requests

    step do
      #puts "[#{Time.now}] Getting action from queue: #{restmq_queue}"
      request = @queue.dequeue(restmq_queue)
      #p request
      unless request.nil?
        command = request['value'].split ','
        case command[0]
        when 'boards'
          collect_boards
        when 'thread'
          collect_thread command[1], command[2]
        when 'threads'
          collect_threads command[1]
        end
      end
      !request.nil?
    end
  end

  def collect_thread(board, thread_no)
    # TODO: Guardar los posts recibidos y enviar el thread a la cola de pruned si ha desaparecido
    log "Collecting the post of /#{board}/#{thread_no}/"
    thread_resp = @fourchan.thread(board, thread_no)

    if thread_resp
      log "#{thread_resp['posts'].length} posts"
      thread_resp['posts'].
        each do |post|
        _post = Post.new(
          post['com'],
          post['sub'] || '',
          post['no'],
          post['time'],
          false, false # For now
        )

        image = Image.new(post['md5']) unless post['md5'].nil?

        tripcode = Tripcode.new(post['trip']) unless post['trip'].nil?

        passyear = PassYear.new(post['since4pass']) unless post['since4pass'].nil?

        user = User.new(post['id']) unless post['id'].nil?

        country = Country.new(post['country_name'], post['country']) unless
          post['country_name'].nil? or post['country'].nil?

        tag = Tag.new(post['tag']) unless post['tag'].nil?

        @neo4j.insert_post_info_if_new(board,
                                       thread_no,
                                       _post,
                                       image,
                                       tripcode,
                                       passyear,
                                       user,
                                       country,
                                       tag
                                      )
      end
    else
      @queue.enqueue Queues.pruned_threads, "#{board},#{thread_no}"
    end
  end

  def collect_threads(board)
    # TODO: Guardar los threads que se encuentren y enviarlos por la cola de threads
    log "Collecting all the threads in /#{board}/"
    @fourchan.threads(board).
      map { |page| page['threads'].map { |thread| thread['no'] } }.flatten.
      each do |thread_no|
      
      @neo4j.add_thread_unless_found board, thread_no
      @queue.enqueue Queues.threads, "#{board},#{thread_no}"
    end
    
    
  end
  
  def step
    while true
      r = yield
      unless r
        @sleep += 1
      else
        @sleep = 1
      end
      puts "[#{Time.now}] Waiting #{@sleep} seconds"
      sleep @sleep
    end
  end

  def log(msg)
    puts "[#{Time.now}] #{msg}"
  end
    
  
  def collect_boards
    log "Collecting all the boards"
    boards = @fourchan.boards

    boards['boards'].map do |board|
      Board.new board['board'],
                board['ws_board'] == 0,
                board['bump_limit'],
                board['image_limit'],
                !board['spoilers'].nil?
      
    end.each do |board|
      @neo4j.add_board board unless @neo4j.board_exists? board
      @queue.enqueue Queues.boards, board.name
    end
  end
end
