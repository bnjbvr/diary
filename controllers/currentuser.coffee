qs = require 'querystring'

Utils = require './utils'

Users = require '../models/users'
Backend = require '../models/backend'
PublicClient = require '../models/public'
Database = require '../models/database'

showErrorPage = (user, res) ->
    res.render 'loggedin',
        flash: user.session.getFlash()

exports.feed = (req, res) ->
    entity = req.signedCookies.entity
    user = Users.Get entity

    Backend.GetFeed user, (err, essays) =>
        if err
            user.pushError err
            showErrorPage user, res
            return

        user.session.cleanInfos()
        for e in essays
            e.readLink = '/friend?user=' + qs.escape(e.entity) + '&id=' + qs.escape e.id
            e.pageLink = Utils.MakePageLink e.entity
        res.render 'all',
            essays: essays
            flash: user.session.getFlash()

exports.page = (req, res) ->
    entity = req.param 'user'
    user = Users.Get req.signedCookies.entity
    validCheck = Utils.CheckValidEntity entity
    if validCheck.error
        user.pushError validCheck.error
        showErrorPage user, res
        return

    Backend.GetAllByEntity user, entity, (err, essays, profile) =>
        if err
            user.pushError err
            showErrorPage user, res
            return

        essays = essays.map (p) =>
            p.readLink = '/friend?user=' + qs.escape(entity) + '&id=' + qs.escape p.id
            p

        res.render 'entity_all',
            essays: essays,
            entity: entity if entity != user.entity
            profile: profile
            flash: user.session.getFlash()

exports.allByCurrent = (req, res) ->
    entity = req.signedCookies.entity
    user = Users.Get entity

    Backend.GetEssays user, (err, essays) =>
        if err
            user.pushError err
            showErrorPage user, res
            return

        user.session.cleanInfos()

        for e in essays
            e.readLink = '/read?user=' + qs.escape(entity) + '&id=' + qs.escape e.id

        res.render 'user_all',
            essays: essays
            flash: user.session.getFlash()


exports.subs = (req, res) ->
    entity = req.signedCookies.entity
    user = Users.Get entity

    Backend.GetSubscriptions user, (err, subs) ->
        if err
            user.pushError err
            showErrorPage user, res
            return

        subscriptions = subs.map (s) ->
            s.pageLink = Utils.MakePageLink s.profile.entity
            s

        Backend.GetSubscribers user, (err2, subs2) ->
            if err2
                user.pushError err2
                subscribers = []
            else
                subscribers = subs2.map (s) ->
                    s.pageLink = Utils.MakePageLink s.entity
                    s

            res.render 'subs_list',
                subscribers: subscribers
                subscriptions: subscriptions
                flash: user.session.getFlash()

exports.addSub = (req, res) ->
    entity = req.signedCookies.entity
    user = Users.Get entity

    # check input
    subscription = req.param 'entity'
    validCheck = Utils.CheckValidEntity subscription
    if validCheck.error
        user.pushError validCheck.error
        res.redirect '/subs'
        return

    subscription = validCheck.entity
    subTent = PublicClient.Get subscription, (err, _) =>
        if err
            user.pushError err
            res.redirect '/subs'
            return

        Backend.AddSubscription user, subscription, (err2) =>
            if err2
                user.pushError err2
            res.redirect '/subs'

exports.friend = (req, res) ->
    id = req.param 'id'
    entity = req.param 'user'
    user = Users.Get req.signedCookies.entity

    if not id
        user.pushError 'Missing parameter: id'
        showErrorPage user, res
        return

    validCheck = Utils.CheckValidEntity qs.unescape entity
    if validCheck.error
        user.pushError validCheck.error
        showErrorPage user, res
        return
    entity = validCheck.entity

    Backend.GetFriendEssayById user, entity, id, (err, essay, profile) =>
        if err
            user.pushError err
            showErrorPage user, res
            return

        res.render 'friend',
            essay:
                title: essay.content.title
                summary: Utils.StripScripts essay.content.excerpt
                content: Utils.StripScripts essay.content.body
            profile: profile
            entity: {value: entity, pageLink: Utils.MakePageLink entity} if entity != user.entity
            flash: user.session.getFlash()

exports.formNew = (req, res) ->
    user = Users.Get req.signedCookies.entity

    if user.session.flash.error.length == 0
        user.session.cleanInfos()

    res.render 'form',
        form: user.session.form
        flash: user.session.getFlash()

exports.formEdit = (req, res) ->
    entity = req.signedCookies.entity
    user = Users.Get entity
    id = req.param 'id'

    if not id
        user.session.pushError 'No id when editing a post'
        res.redirect '/my'
        return

    Backend.GetEssayById user, id, (err, e) ->
        if err
            user.session.pushError err
            res.redirect '/my'
            return

        isPrivate = false
        if e.permissions and e.permissions.public != undefined and not e.permissions.public
            isPrivate = true

        form =
            title: e.content.title || ''
            content: e.content.body || ''
            summary: e.content.excerpt || ''
            update: e.id
            isPrivate: isPrivate

        res.render 'form',
            form: form
            flash: user.session.getFlash()

exports.deleteById = (req, res) ->
    entity = req.signedCookies.entity
    user = Users.Get entity
    id = req.param 'id'

    if not id
        user.pushError 'no id when deleting an essay'
        res.redirect '/my'
        return

    Backend.DeleteEssayById user, id, (err) ->
        if err
            user.ushError err
            res.redirect '/edit/' + id
        else
            user.pushSuccess 'Deletion of essay was successful.'
            Database.MaybeDeleteFromFeed {entity: entity, id: id}, (err) =>
                res.redirect '/my'

exports.globalFeed = (req, res) ->
    user = Users.Get req.signedCookies.entity
    Database.GetGlobalFeed (err, posts) =>
        if err
            user.pushError 'When retrieving the global feed, ' + err
            showErrorPage user, res
            return
        posts = posts.map (p) ->
            p.readLink = '/friend?user=' + qs.escape(p.entity) + '&id=' + qs.escape p.id
            p
        res.render 'global',
            essays: posts
            flash: user.session.getFlash()

exports.newEssay = (req, res) ->
    entity = req.signedCookies.entity
    user = Users.Get entity

    title = req.param 'title'
    summary = req.param 'summary'
    content = req.param 'content'
    isPrivate = !! req.param 'isPrivate'
    updateId = req.param 'update'

    if not content or content.length == 0
        user.session.form =
            title: title
            summary: summary
            isPrivate: isPrivate
            update: updateId

        user.pushError 'Missing parameter: no content'
        res.redirect '/my/new'
        return

    essay =
        title: title || ''
        excerpt: summary || ''
        body: content

    if updateId
        vbING = 'updating'
        noun = 'Update'
    else
        vbING = 'creating'
        noun = 'Creation'

    cb = (err, post) =>
        if err
            user.pushError 'An error happened when ' + vbING + ' post: ' + err
        else
            user.pushSuccess noun + ' of your essay successful.'
            user.session.cleanInfos()
            if not isPrivate
                Database.SaveForGlobalFeed post, (err2) =>
                    if err2
                        user.pushError 'Error when adding the post to the global feed: ' + err2
                    res.redirect '/my'
            else
                Database.MaybeDeleteFromFeed post, (_) =>
                    res.redirect '/my'

    if updateId
        Backend.UpdateEssay user, updateId, essay, isPrivate, cb
    else
        Backend.CreateEssay user, essay, isPrivate, cb

