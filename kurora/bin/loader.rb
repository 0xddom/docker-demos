require 'crawler'
require 'watcher'
require 'analyzer'

class Loader

  MODES = {
    crawler: CrawlerMode,
    watch: WatcherMode,
    analyze: AnalysisMode,
  }
  
  def initialize(args)
    puts "Selected mode: #{args[0]}"

    unless args[0].nil?
      mode = MODES[args[0].to_sym].new args.drop 1
      mode.run
    end
  end
end

Loader.new $*
