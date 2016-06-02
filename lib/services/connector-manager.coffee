_ = require 'lodash'
async = require 'async'
helper = require './imdone-helper'
log = require('debug/browser') 'imdone-atom:connector-manager'
Task = require 'imdone-core/lib/task'
{Emitter} = require 'atom'

syncTasks = (client, repo) ->
  (tasks) ->
    tasks = [tasks] unless _.isArray tasks
    client.syncTasks repo, tasks, (err, tasks) ->
      return if err # DOING:0 Do something with this error id:414
      async.eachSeries tasks,
        (task, cb) -> repo.modifyTask(new Task(task, true), cb)
        (err) -> repo.saveModifiedFiles ()->

module.exports =
class ConnectorManager extends Emitter
  products: null

  constructor: (@repo) ->
    super
    @client = require('./imdoneio-client').instance
    @syncTasks = syncTasks @client, @repo
    @handleEvents()
    @onAuthenticated() if @client.isAuthenticated
    # READY:30 Check for updates to products/connectors and update @products with changes id:415

  handleEvents: ->
    # DONE:310 Listen for events on repo and update imdone.io with tasks, but on first run we'll have to queue them up for after auth +story id:416

    @client.on 'product.linked', (product) =>
      @setProduct product, (err, product) =>
        @emit 'product.linked', product unless err

    @client.on 'product.unlinked', (product) =>
      @setProduct product, (err, product) =>
        @emit 'product.unlinked', product unless err

    @client.on 'authenticated', => @onAuthenticated()
    # @client.on 'connector.enabled', (connector) => @setConnector connector
    #
    # @client.on 'connector.disabled', (connector) => @setConnector connector
    #
    # @client.on 'connector.changed', (connector) => @setConnector connector
    #
    # @client.on 'connector.created', (connector) => @setConnector connector

  onRepoInit: () ->
    return if @project || @initialized
    @client.getOrCreateProject @repo, (err, project) =>
      return if err
      @project = project
      @syncTasks @repo.getTasks()
      @addTaskListeners()
      @emit 'project.found', project

  onAuthenticated: () ->
    console.log('authenticated');
    @onRepoInit() if @repo.initialized
    @repo.on 'initialized', => @onRepoInit()

  addTaskListeners: ->
    @repo.removeListener 'task.found', @syncTasks
    @repo.on 'task.found', @syncTasks

  projectId: () -> @client.getProjectId @repo

  getProducts: (cb) ->
    cb = (()->) unless cb
    return cb(null, @products) if @products
    @client.getProducts @projectId(), (err, products) =>
      return cb err  if err
      @enhanceProduct product for product in products
      @products = products
      cb null, products

  getProduct: (provider, cb) ->
    @getProducts (err, products) ->
      cb err, _.find products, name: provider

  setProduct: (newProduct, cb) ->
    cb = (()->) unless cb
    @getProduct newProduct.name, (err, product) ->
      return cb err  if err
      _.assign product, newProduct
      product.linked = newProduct.linked
      _.set product, 'connector.enabled', _.get(newProduct, 'connector.enabled')
      cb null, product

  setConnector: (connector, cb) ->
    @getProduct connector.name, (err, product) =>
      return cb err  if err
      product.connector = connector
      @enhanceProduct  product
      cb null, connector

  saveConnector: (connector, cb) ->
    cb = (()->) unless cb
    return @createConnector connector, cb unless connector.id
    @updateConnector connector, cb

  createConnector: (connector, cb) ->
    @client.createConnector @repo, connector, cb

  updateConnector: (connector, cb) ->
    @client.updateConnector @repo, connector, (err, connector) =>
      return cb err if err
      @setConnector connector, cb

  enableConnector: (connector, cb) ->
    @client.enableConnector @repo, connector, (err, connector) =>
      return cb err if err
      @setConnector connector, cb

  disableConnector: (connector, cb) ->
    @client.disableConnector @repo, connector, (err, connector) =>
      return cb err if err
      @setConnector connector, cb

  getGitOrigin: () ->
    repo = helper.repoForPath @repo.getPath()
    return null unless repo
    repo.getOriginURL()

  enhanceProduct: (product) ->
    product.connector.defaultSearch = product.defaultSearch if product.connector
    _.mixin product,
      isLinked: () -> this.linked
      isEnabled: () -> this.linked && this.connector && this.connector.enabled
