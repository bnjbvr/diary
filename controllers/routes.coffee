middlewares = require './middlewares'

CurrentUser = require './currentuser'
Public = require './public'
Auth = require './auth'

Csrf = middlewares.Csrf
CheckAuth = middlewares.CheckAuth

exports.setup = (app) ->
    app.get '/', Csrf, CheckAuth, CurrentUser.feed

    app.get '/subs', Csrf, CheckAuth, CurrentUser.subs
    app.post '/subs/new', Csrf, CheckAuth, CurrentUser.addSub
    app.get '/friend', Csrf, CheckAuth, CurrentUser.friend # TODO rename that
    app.get '/page', Csrf, CheckAuth, CurrentUser.page # TODO rename that

    # TODO make URI consistent
    app.get '/my', Csrf, CheckAuth, CurrentUser.allByCurrent
    app.get '/my/new', Csrf, CheckAuth, CurrentUser.formNew
    app.post '/new', CheckAuth, CurrentUser.newEssay
    app.get '/edit/:id', Csrf, CheckAuth, CurrentUser.formEdit
    app.get '/del/:id', Csrf, CheckAuth, CurrentUser.deleteById
    app.get '/global', Csrf, CheckAuth, CurrentUser.globalFeed # TODO should be public

    app.get '/read', Public.Reader

    app.get '/login', Csrf, Auth.loginForm
    app.post '/login', Auth.login
    app.get '/cb', Auth.callback
    app.get '/logout', Auth.logout
