# frozen_string_literal: true

require 'discordrb'
require 'open-uri'
require 'nokogiri'
require 'dotenv'
require 'bundler'
require 'active_support/multibyte'

Dotenv.load

BOT_TOKEN = ENV['access_token']
JA_REGEX = /｛[^｛｝]+｝/.freeze
EN_REGEX = /"[^"]+"/.freeze

JA_BASE_WIKIPEDIA_URL = 'https://ja.wikipedia.org/wiki/'
BASE_WIKIPEDIA_URL = 'https://wikipedia.org/wiki/'
HALFWIDTH_SPACE = ' '
FULlWIDTH_SPACE = '　'

EMBED_TITLE_LENGTH_LIMIT = 256
EMBED_VALUE_LENGTH_LIMIT = 1024

class String
  def mb_chars
    ActiveSupport::Multibyte.proxy_class.new(self)
  end

  def truncate(length, omission = '…')
    text = dup

    length_with_room_for_omission = length - omission.mb_chars.length
    chars = text.mb_chars
    stop = length_with_room_for_omission

    (chars.length > length ? chars[0...stop] + omission : text).to_s
  end
end

def sanitize(word)
  word.gsub!(/^#{HALFWIDTH_SPACE}|#{HALFWIDTH_SPACE}$/, '')
  word.gsub!(/^#{FULlWIDTH_SPACE}|#{FULlWIDTH_SPACE}$/, '')
  word.gsub!(/#{FULlWIDTH_SPACE}|#{HALFWIDTH_SPACE}/, '_')

  word
end

def title_and_description_of(wikipedia_page)
  doc = nil

  begin
    doc = Nokogiri::HTML(URI.open(wikipedia_page))
  rescue StandardError
    return
  end

  return unless doc

  title = doc.xpath('/html/head/title').text.truncate(EMBED_TITLE_LENGTH_LIMIT)
  description = doc.xpath('//*[@id="mw-content-text"]/div[1]/p[3]').text.truncate(EMBED_VALUE_LENGTH_LIMIT - "\n#{wikipedia_page}".length) # the first paragraph in the body.

  { title: title, description: "#{description}\n#{wikipedia_page}" }
end

def embed_from(title_and_description)
  return unless title_and_description

  Discordrb::Webhooks::EmbedField.new(name: title_and_description[:title],
                                      value: title_and_description[:description])
end

bot = Discordrb::Bot.new token: BOT_TOKEN

bot.message do |event|
  message_text = event.content
  wikipedia_link_embeds = message_text.scan(JA_REGEX).map do |ja_word|
    ja_word.gsub!(/[｛｝]/, '')
    ja_word = sanitize(ja_word)
    ja_word = CGI.escape(ja_word)

    wikipedia_page = JA_BASE_WIKIPEDIA_URL + ja_word
    embed_from(title_and_description_of(wikipedia_page))
  end

  wikipedia_link_embeds += message_text.scan(EN_REGEX).map do |en_word|
    en_word.gsub!('"', '')
    en_word = sanitize(en_word)

    wikipedia_page = BASE_WIKIPEDIA_URL + en_word
    embed_from(title_and_description_of(wikipedia_page))
  end

  wikipedia_link_embeds.compact!

  embed = Discordrb::Webhooks::Embed.new
  embed.fields = wikipedia_link_embeds
  event.respond('', false, embed) unless wikipedia_link_embeds.empty?
end

bot.run
