qs      = require 'querystring'

# Constants
ESSAY_TYPE = 'https://tent.io/types/essay/v0#'
SUBSCRIPTION_TYPE = 'https://tent.io/types/subscription/v0#'

ESSAY_SUB = 'https://tent.io/types/subscription/v0#https://tent.io/types/essay/v0'

###
# Retrieves all essays of the user.
#
# user -> a User instance (see also users.coffee)
# cb -> function(maybeError, [post])
###
exports.GetEssays = (user, cb) ->
    tcb = (err, headers, body) =>
        if err
            console.error 'Backend.GetEssays: when fetching essays of ' + user.entity + ' :' + err
            cb 'Error when fetching essays: ' + err
            return

        essays = body.posts
        # replaces blank titles by "untitled"
        if essays.map
            essays = essays.map (a) ->
                if not a.content or not a.content.title or a.content.title.length == 0
                    a.content.title = '(untitled)'
                a

        cb null, essays

    user.tent.query(tcb).types(ESSAY_TYPE).entities(user.entity)


exports.GetFeed = (user, cb) ->
    tcb = (err, headers, body) =>
        if err
            console.error 'Backend.GetFeed: when fetching feed of ' + user.entity + ' :' + err
            cb 'Error when fetching essays: ' + err
            return

        essays = body.posts
        # replaces blank titles by "untitled"
        if essays.map
            essays = essays.map (a) =>
                if not a.content or not a.content.title or a.content.title.length == 0
                    a.content.title = '(untitled)'

                body.profiles ?= {}
                a.profile = body.profiles[a.entity]
                if not a.profile
                    a.profile = {name: ''}

                a

        cb null, essays

    user.tent.query( {profiles: 'entity'}, tcb ).types(ESSAY_TYPE)
    # TODO maybe factorize this with getessays

exports.GetAllByEntity = (user, entity, cb) ->
    tcb = (err, headers, body) =>
        if err
            console.error 'Backend.GetAllFromFriend for ' + user.entity + ': ' + err
            cb 'Error when fetching all essays from  ' + entity + ': ' + err
            return

        essays = body.posts.map (a) ->
            if not a.content or not a.content.title or a.content.title.length == 0
                a.content.title = '(untitled)'
            a
        body.profiles ?= {}
        profile = body.profiles[entity] || {name: entity}
        cb null, essays, profile

    user.tent.query( {profiles: 'entity'}, tcb ).entities(entity).types(ESSAY_TYPE)

exports.GetFriendEssayById = (user, entity, id, cb) ->
    tcb = (err, headers, body) =>
        if err
            console.error 'Backend.GetFriendEssayById: fetching essay of ' + user.entity + ' with id ' + id + ' : ' + err
            cb 'Error when fetching a single essay: ' + err
            return

        essay = body.post

        body.profiles ?= {}
        profile = body.profiles[entity] || {}
        profile.name ?= ''
        profile.bio ?= ''

        cb null, essay, profile

    user.tent.get(id, entity, {profiles: 'entity'}, tcb)


exports.AddSubscription = (user, entity, cb) ->
    tcb = (err, headers, body) =>
        if err
            console.error 'Backend.SubscribeFriend: error for ' + user.entity + ' when subscribing on ' + entity + ': ' + err

            cb 'Error when subscribing to an entity: ' + err
            return
        cb null

    subscription =
        type: ESSAY_TYPE

    user.tent.create(ESSAY_SUB, tcb)
             .content(subscription)
             .mentions(entity)

exports.GetSubscriptions = (user, cb) ->
    tcb = (err, headers, body) =>
        if err
            console.error 'Backend.GetSubscriptions: for ' + user.entity + '\n' + err
            cb 'Error when retrieving your subscriptions: ' + err
            return

        subs = body.posts
        subs = subs.map (s) =>
            subEntity = if s.mentions.length > 0 then s.mentions[0] else null
            subEntity = if subEntity.entity then subEntity.entity else null
            if not subEntity
                s.profile = {name: '?'}
                return s
            body.profiles ?= {}
            s.profile = body.profiles[subEntity] || {}
            s.profile.name ?= subEntity
            s.profile.entity = subEntity
            s
        cb null, subs

    user.tent.query({ profiles: 'mentions' }, tcb).types(ESSAY_SUB).entities(user.entity)


exports.GetSubscribers = (user, cb) ->
    tcb = (err, headers, body) =>
        if err
            console.error 'Backend.GetSubscribers: for ' + user.entity + '\n' + err
            cb 'Error when retrieving your subscribers: ' + err
            return

        subs = body.posts
        subs = subs.map (s) =>
            subEntity = s.entity
            body.profiles ?= {}
            s.profile = body.profiles[subEntity] || {}
            s.profile.name ?= subEntity
            s
        cb null, subs

    user.tent.query({ profiles: 'entity' }, tcb).types(ESSAY_SUB).mentions(user.entity)


GetEssayById = exports.GetEssayById = (user, id, cb) ->
    tcb = (err, headers, body) =>
        if err
            console.error 'Backend.GetEssayById: fetching essay of ' + user.entity + ' with id ' + id + ' : ' + err
            cb 'Error when fetching a single essay: ' + err
            return

        essay = body.post
        cb null, essay

    user.tent.get id, tcb


exports.DeleteEssayById = (user, id, cb) ->
    user.tent.delete id, (err) ->
        if err
            console.error 'Backend.DeleteEssayById: deleting essay of ' + user.entity + ' with id ' + id + ' : ' + err
            cb 'Error when deleting an essay: ' + err
        cb null


exports.UpdateEssay = (user, id, essay, isPrivate, cb) ->
    GetEssayById user, id, (err, formerEssay) =>
        if err
            cb err
            return

        tcb = (err2, headers, body) =>
            if err2
                console.error 'Backend.UpdateEssay: ' + err2
                cb err2
                return
            cb null, body.post

        user.tent.update(id, formerEssay.version.id, tcb)
            .type(ESSAY_TYPE)
            .content(essay)
            .permissions(!isPrivate)

exports.CreateEssay = (user, essay, isPrivate, cb) ->
    tcb = (err, headers, body) =>
        if err
            console.error 'Backend.CreateEssay: ' + err
            cb err
            return
        cb null, body.post

    user.tent.create(ESSAY_TYPE, tcb)
        .publishedAt( +new Date() )
        .content(essay)
        .permissions(!isPrivate)
