express = require 'express'
http    = require 'http'
path    = require 'path'

config = require './config'                 # port on which to run the app
routes = require './controllers/routes'

app = new express()
app.configure () ->
    app.set 'port', config.port

    app.set 'views', __dirname + '/views'
    app.set 'view engine', 'jade'
    app.use express.static path.join(__dirname, 'public')

    app.use express.bodyParser()
    app.use express.methodOverride()
    app.use express.cookieParser 'secret'
    app.use express.session()
    app.use express.csrf()
    app.use app.router

    app.enable 'trust proxy'

    # helpers for jade
    # TODO ugly
    app.locals.formatDate = (n) ->
        date = new Date n
        'the ' + (1+date.getMonth()) + '/' + date.getDate() + '/' + date.getFullYear() + ' at ' + date.getHours() + ':' + date.getMinutes() + ':' + date.getSeconds()

app.configure 'development', () ->
    app.use express.errorHandler()
    app.locals.pretty = true

routes.setup app

server = http.createServer(app).listen app.get('port'), () ->
    console.log 'Express server listening on port ' + app.get 'port'
