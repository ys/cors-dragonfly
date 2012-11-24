require 'sinatra'
require 'slim'
require 'base64'
require 'json'
require 'mongoid'
require 'dragonfly'
require 'nokogiri'

BUCKET = 'eatcpcks'
SECRET_ACCESS_KEY = ENV['AWS_SECRET_ACCESS_KEY']
ACCESS_KEY_ID = ENV['AWS_ACCESS_KEY_ID']

app = Dragonfly[:images]

app.define_macro_on_include(Mongoid::Document, :image_accessor)

Mongoid.load!('mongoid.yml')

app.configure_with(:imagemagick) do |c|
  c.url_format = '/images/:job/:basename.:format'
end

app.datastore = Dragonfly::DataStorage::S3DataStore.new

app.datastore.configure do |c|
  c.bucket_name = BUCKET
  c.access_key_id = ACCESS_KEY_ID
  c.secret_access_key = SECRET_ACCESS_KEY
  c.region = 'eu-west-1'                        # defaults to 'us-east-1'
  c.storage_headers = {'x-amz-acl' => 'public-read'}       # defaults to {'x-amz-acl' => 'public-read'}
  c.url_scheme = 'https'                        # defaults to 'http'
end#

use Dragonfly::Middleware, :images

class Picture
  include Mongoid::Document

  field :image_uid
  field :image_name

  image_accessor :image
end

get '/:image_id' do |image_id|
  @image = Picture.find(image_id).image
  slim :show
end

get '/:image_id/direct' do |image_id|
  redirect Picture.find(image_id).image.remote_url
end

get '/:image_id/thumb' do |image_id|
  Picture.find(image_id).image.thumb("100x100#").to_response(env)
end

get '/' do
  slim :index
end

post '/' do
  if params[:image]
    image_xml = Nokogiri::XML::Document.parse(params[:image])
    image_uid = image_xml.xpath("//PostResponse/Key").first.content
    filename = image_xml.xpath("//PostResponse/Key").first.content.split('/')[-1]
    picture = Picture.create(image_uid: image_uid, image_name: filename)
  else
    image = params[:file][:tempfile]
    picture = Picture.create(image: image, image_name: filename)
  end
  redirect "/#{picture.id}"
end


def signature(options = {})
  Base64.encode64(
    OpenSSL::HMAC.digest(
      OpenSSL::Digest::Digest.new('sha1'),
      SECRET_ACCESS_KEY,
      policy({ secret_access_key: SECRET_ACCESS_KEY })
    )
  ).gsub(/\n/, '')
end

def policy(options = {})
  Base64.encode64(
    {
      expiration: (Time.new + 60 ).utc.strftime('%Y-%m-%dT%H:%M:%S.000Z'),
      conditions: [
        { bucket: BUCKET },
        { acl: 'public-read' },
        { success_action_status: '201' },
        ['starts-with', '$key', ''],
        ['starts-with', '$Content-Type', '']
      ]
    }.to_json
  ).gsub(/\n|\r/, '')
end
