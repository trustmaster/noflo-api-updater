noflo = require 'noflo'
uuid = require 'uuid'

exports.getComponent = ->
  c = new noflo.Component

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

  c.outPorts = new noflo.OutPorts
    firstpoint:
      datatype: 'int'
    points:
      datatype: 'object'
      description: 'pointing'

  noflo.helpers.WirePattern c,
    in: ['x', 'y', 'z']
    out: ['point', 'firstpoint']
    group: true
    forwardGroups: true
    async: true
  , (data, groups, outs, callback) ->
    outs.firstpoint.send data.x
    outs.firstpoint.disconnect()

    outs.points.send data
    outs.points.disconnect()
    do callback
