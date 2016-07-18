noflo = require 'noflo'
uuid = require 'uuid'

exports.getComponent = ->
  c = new noflo.Component
  c.icon = 'code-fork'
  c.description = 'eh'
  c.inPorts.add 'w',
    required: true
    datatype: 'int'
  .add 'x',
    required: true
    datatype: 'int'
  .add 'y',
    required: true
    datatype: 'int'
  .add 'z',
    datatype: 'int'

  c.outPorts.add 'point',
    datatype: 'int'
    description: 'pointing'

  noflo.helpers.WirePattern c,
    in: ['x']
    params: ['y', 'z']
    out: 'point'
    group: true
    async: true
  , (data, groups, out, callback) ->
    out.send data
    out.disconnect()
    do callback
