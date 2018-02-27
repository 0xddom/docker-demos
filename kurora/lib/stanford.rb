include Java
require 'stanford-ner'
require 'pathname'
require 'graph'
require 'nokogiri'

java_import Java::edu.stanford.nlp.ie.crf.CRFClassifier

class Stanford

  attr_accessor :classifier
  
  def initialize(c)
    @classifier = c
  end

  def process(text)
    xml = Nokogiri::XML("<wis>" + (@classifier.classifyToString text, "xml", true).to_s + "</wis>")

    xml.xpath('//wis//wi').find_all do |e|
      e['entity'] != 'O'
    end.map do |e|
      Entity.new e.children[0].to_s, e['entity']
    end
  end
  
  def self.create_classifier
    Stanford.new CRFClassifier.getClassifierNoExceptions (home + classifiers + english).to_s
  end

  private
  
  def self.home
    Pathname.new './vendor/stanford'
  end

  def self.classifiers
    Pathname.new 'stanford-ner-2015-12-09/classifiers'
  end

  def self.english
    Pathname.new 'english.all.3class.distsim.crf.ser.gz'
  end
 
end
