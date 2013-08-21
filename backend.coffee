# Constants
ESSAY_TYPE = 'https://tent.io/types/essay/v0#'

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

    user.tent.query(tcb).types(ESSAY_TYPE)


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

        tcb = (err2, _) =>
            if err2
                console.error 'Backend.UpdateEssay: ' + err2
                cb err2
                return
            cb null

        user.tent.update(id, formerEssay.version.id, tcb)
            .type(ESSAY_TYPE)
            .content(essay)
            .permissions(!isPrivate)


exports.CreateEssay = (user, essay, isPrivate, cb) ->
    tcb = (err, _) =>
        if err
            console.error 'Backend.CreateEssay: ' + err
            cb err
            return
        cb null

    user.tent.create(ESSAY_TYPE, tcb)
        .publishedAt( +new Date() )
        .content(essay)
        .permissions(!isPrivate)
