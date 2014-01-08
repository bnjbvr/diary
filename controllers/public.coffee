Utils = require './utils'

PublicClient = require '../models/public'
Backend = require '../models/backend'

exports.Reader = (req, res) ->
    id = req.param 'id'
    entity = req.param 'user'

    if not id
        res.send 400, 'Missing parameter: id'
        return

    validCheck = Utils.CheckValidEntity entity
    if validCheck.error
        res.send 400, validCheck.error
        return
    entity = validCheck.entity

    PublicClient.Get entity, (err, tent) ->
        if err
            res.send 500, err
            return

        Backend.GetEssayById {tent:tent}, id, (err2, essay) ->
            if err2
                res.send 500, err
                return

            res.render 'read',
                essay:
                    title: essay.content.title
                    summary: Utils.StripScripts essay.content.excerpt
                    content: Utils.StripScripts essay.content.body


