express = require "express"
io = require "socket.io"
twitter = require "twitter"
util = require "util"
events = require "events"
fs = require "fs"
path = require "path"
_ = require "underscore"

app = express.createServer()
app.use express.bodyParser()
app.use express.errorHandler()
app.use express.static "#{__dirname}/web"

app.get "/", (req, res) ->
  res.sendfile("#{__dirname}/web/index.html")

io = io.listen app
port = parseInt(process.env.PORT, 10) or 1337
app.listen port
console.log "Listening on http://localhost:#{port}/"

twitter_config = JSON.parse(fs.readFileSync(path.join(process.env.HOME, ".twitter-auth.json"), "utf8"))

t = new twitter(twitter_config)

class TwitterStream extends events.EventEmitter
  constructor: ->
    @tweets = []

  add: (tweet) =>
    if tweet.delete?
      id = tweet.delete.status.id
      @tweets = _.reject @tweets, (i) -> i.id == id
      @emit "delete", id
    else if tweet.friends?
      @emit "friends", tweet.friends
    else if tweet.created_at?
      @tweets.push tweet
      @tweets = (_.sortBy @tweets, "id").reverse()[..20]
      @emit "tweet", tweet

  last: =>
    @tweets

stream = new TwitterStream()

t.stream "user", (s) ->
  s.on "data", (data) ->
    stream.add data
  s.on "error", (error) ->
    console.log util.inspect error
    stream.emit "error", error
  s.on "end", ->
    console.log "****** ERROR: Twitter stream terminated!"
    stream.emit "end", {}

t.getHomeTimeline (data) ->
  for tweet in data
    stream.add tweet

io.sockets.on "connection", (socket) ->
  streamEmitter = (data) ->
    socket.emit "tweet", data
  for tweet in stream.last().reverse()
    streamEmitter(tweet)
  stream.on "tweet", streamEmitter
  stream.on "delete", (id) -> socket.emit "delete", id
  stream.on "friends", (friends) -> socket.emit "friends", friends
  socket.on "tweet", (text) ->
    t.updateStatus text, (data) ->
      socket.emit "tweetresult", data
  socket.on "disconnect", ->
    stream.removeListener "data", streamEmitter
