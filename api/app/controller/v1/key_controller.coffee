_ = require "underscore"
async = require "async"

{ ApiaxleController, ListController, CreateController } = require "../controller"
{ NotFoundError, AlreadyExists } = require "../../../lib/error"

class exports.ListKeys extends ListController
  @verb = "get"

  path: -> "/v1/keys"

  desc: -> "List all of the available keys."

  docs: ->
    """
    ### Supported query params
    * from: Integer for the index of the first key you want to
      see. Starts at zero.
    * to: Integer for the index of the last key you want to
      see. Starts at zero.
    * resolve: if set to `true` then the details concerning the listed
      keys will also be printed. Be aware that this will come with a
      minor performace hit.

    ### Returns

    * Without `resolve` the result will be an array with one key per
      entry.
    * If `resolve` is passed then results will be an object with the
      key name as the key and the details as the value.
    """

  modelName: -> "keyFactory"

class exports.CreateKey extends ApiaxleController
  @verb = "post"

  desc: -> "Provision a new key."

  docs: ->
    """
    ### JSON fields supported

    #{ @app.model( 'keyFactory' ).getValidationDocs() }

    ### Returns

    * The newly inseted structure (including the new timestamp
      fields).
    """

  middleware: -> [ @mwContentTypeRequired( ), @mwKeyDetails( ) ]

  path: -> "/v1/key/:key"

  execute: ( req, res, next ) ->
    # error if it exists
    if req.key?
      return next new AlreadyExists "'#{ req.key.id }' already exists."

    @app.model( "keyFactory" ).create req.params.key, req.body, ( err, newObj ) =>
      return next err if err

      @json res, newObj.data

class exports.ViewKey extends ApiaxleController
  @verb = "get"

  desc: -> "Get the definition of a key."

  docs: ->
    """
    ### Returns

    * The key object (including timestamps).
    """

  middleware: -> [ @mwKeyDetails( valid_key_required=true ) ]

  path: -> "/v1/key/:key"

  execute: ( req, res, next ) ->
    # we want to add the list of APIs supported by this key to the
    # output
    req.key.supportedApis ( err, apiNameList ) =>
      return next err if err

      # merge the api names with the current output
      output = req.key.data
      output.apis = apiNameList

      @json res, req.key.data

class exports.DeleteKey extends ApiaxleController
  @verb = "delete"

  desc: -> "Delete a key."

  docs: ->
    """
    ### Returns

    * `true` on success.
    """

  middleware: -> [ @mwKeyDetails( valid_key_required=true ) ]

  path: -> "/v1/key/:key"

  execute: ( req, res, next ) ->
    model = @app.model "keyFactory"

    model.del req.params.key, ( err, newKey ) =>
      return next err if err

      @json res, true

class exports.ModifyKey extends ApiaxleController
  @verb = "put"

  desc: -> "Update a key."

  docs: ->
    """
    Fields passed in will will be merged with the old key details.

    ### JSON fields supported

    #{ @app.model( 'keyFactory' ).getValidationDocs() }

    ### Returns

    * The newly inseted structure (including the new timestamp
      fields).
    """

  middleware: -> [
    @mwContentTypeRequired( ),
    @mwKeyDetails( valid_key_required=true )
  ]

  path: -> "/v1/key/:key"

  execute: ( req, res, next ) ->
    model = @app.model "keyFactory"

    # modify the key
    newData = _.extend req.key.data, req.body

    # re-apply it to the db
    model.create req.params.key, newData, ( err, newKey ) =>
      return next err if err

      @json res, newKey.json

class exports.ViewHitsForKey extends ApiaxleController
  @verb = "get"

  desc: -> "Get hits for a key in the past minute."

  docs: ->
    """
    ### Returns

    * Object where the keys represent timestamp for a given second
      and the values the amount of hits to the Key for that second
    """

  middleware: -> [ @mwKeyDetails( @app ) ]

  path: -> "/v1/key/:key/hits"

  execute: ( req, res, next ) ->
    model = @app.model "hits"
    model.getCurrentMinute "key", req.params.key, ( err, hits ) =>
      return @json res, hits


class exports.ViewHitsForKeyNow extends ApiaxleController
  @verb = "get"

  desc: -> "Get the real time hits for a key."

  docs: ->
    """
    ### Returns

    * Integer, the number of hits to the Key this second.
      Designed light weight real time statistics
    """

  middleware: -> [ @mwKeyDetails( @app ) ]

  path: -> "/v1/key/:key/hits/now"

  execute: ( req, res, next ) ->
    model = @app.model "hits"
    model.getRealTime "key", req.params.key, ( err, hits ) =>
      return @json res, hits

class exports.ViewStatsForKey extends ApiaxleController
  @verb = "get"

  desc: -> "Get stats for a key"

  docs: ->
    """
    ### Returns

    * Object where the keys represent the HTTP status code of the
      endpoint or the error returned by apiaxle (QpsExceededError, for
      example). Each object contains timestamp to hit count pairs.
    """

  middleware: -> [ @mwKeyDetails( @app ) ]

  path: -> "/v1/key/:key/stats"

  execute: ( req, res, next ) ->
    model = @app.model "stats"
    key   = req.params.key
    from  = req.query["from"]
    to    = req.query["to"]
    gran  = req.query["granularity"]

    codes = [200]

    all = []
    all.push (cb) =>
      model.get ["key", key, "200"], gran, from, to, cb

    async.series all, (err, results) =>
      processed = {}
      count     = 0
      for code in codes
        processed[code] = results[count]
      return @json res, processed
