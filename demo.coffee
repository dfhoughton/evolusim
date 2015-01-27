initializationParameters =
  pause: [ 10, 0, 1000, 'minimum pause between ticks' ]
  maxDistance: [ 60, 30, 100, 'maximum distance an organism can see' ]
  initialCreatures:
    stones:
      num: [ 40, 0, 100 ]
    plants:
      num: [ 100, 10, 500 ]
      init:
        bodyColor: '#ffcb0c'
        radius: [ 4, 2, 20, 'plant size' ]
    herbivores:
      num: [ 8, 0, 100 ]
      init:
        bodyColor: '#2b4dcb'
        radius: [ 5, 2, 20, 'body size' ]
    carnivores:
      num: [ 40, 0, 100 ]
      init:
        bodyColor: '#ec2200'
        radius: [ 6, 2, 20, 'body size' ]
byId = (id) -> document.getElementById(id)
trimNum = (n) -> parseFloat n.toPrecision(3)
decamelize = (str) ->
  str = str.replace /([a-z])([A-Z])/g, "$1 $2"
  str.toLowerCase()
titlize = (str) ->
  str.replace /\b[a-z]/g, (s) -> s.charAt(0).toUpperCase() + s.substr(1).toLowerCase()
text = (t) ->
  document.createTextNode(t)
intFormat = (int) ->
  ar = ( '' + int ).split('').reverse()
  ar2 = []
  for v, i in ar
    ar2.push ',' if i && !( i % 3 )
    ar2.push v
  ar2.reverse().join ''
create = (tag, cz) ->
  e = document.createElement(tag)
  e.setAttribute( 'class', cz ) if cz
  e
chartType = 'options'
[ u, makeCharts, loaded ] = [ null, false, false ]
convertParams = (obj=initializationParameters) ->
  copy = {}
  for k,v of obj
    if v instanceof Array
      copy[k] = v[0]
    else if typeof v == 'object'
      copy[k] = convertParams v
    else
      copy[k] = v
  copy
makeInputs = (obj=initializationParameters, parent=byId('options')) ->
  for k,v of obj
    div = create 'div', 'indenter'
    h = create 'div', 'param-header'
    h.innerHTML = decamelize k
    div.appendChild h
    parent.appendChild div
    if v instanceof Array
      makeSlider k, obj, div
    else if /color/i.test k
      makeColorPicker k, obj, div
    else if typeof v == 'boolean'
      makeCheckbox k, obj, div
    else
      makeInputs v, div
makeColorPicker = (label, object, parent) ->
  color = object[label]
  s = create 'input'
  s.type = 'color'
  s.value = color
  h = parent.firstChild
  h.appendChild text(' ')
  h.appendChild s
  sp = create 'span'
  sp.innerHTML = color
  sp.style.fontWeight = 'normal'
  h.appendChild text(' ')
  h.appendChild sp
  s.onchange = ->
    object[label] = s.value
    sp.innerHTML = s.value
makeCheckbox = (label, obj, parent) ->
makeSlider = (label, object, parent) ->
  values = object[label]
  s = create 'input'
  s.type = 'range'
  s.value = values[0]
  s.min = values[1]
  s.max = values[2]
  s.title = d if d = values[3]
  s.step = 1
  sp = create 'span', 'param-value'
  sp.innerHTML = values[0]
  parent.appendChild s
  parent.appendChild sp
  s.onchange = ->
    sp.innerHTML = s.value
    values[0] = Number.parseInt s.value
madeGeneCharts = false
makeUniverse = ->
  p = convertParams()
  p.callback = collectData
  u = new Universe 'universe', p
  unless madeGeneCharts
    for type in [ 'plant', 'herbivore', 'carnivore' ]
      tab = byId "#{type}-chart"
      for gene, v of u.urThing(type).genes
        id = "#{type}-#{gene}"
        div = create 'div', 'chart'
        div.id = id
        tab.appendChild div
        charts = evoData.charts[type] ||= {}
        charts[gene] = geneChartSpec type, gene, id
evoData =
  resetNum: 1
  generation: 0
  charts:
    all:
      Population:
        id: 'chart'
        htitle: 'Time (ticks)'
        vtitle: 'Num. individuals'
        collector: (stats, rows) ->
          counts = Plant: 0, Herbivore: 0, Carnivore: 0
          counts[description.type] += 1 for description in stats
          row = [ evoData.generation, counts.Plant, counts.Herbivore, counts.Carnivore ]
          rows.push row
        names: [ 'Plant', 'Herbivore', 'Carnivore' ]
        colors: [
            -> u.urThing('plant').bodyColor
            -> u.urThing('herbivore').bodyColor
            -> u.urThing('carnivore').bodyColor
          ]
        rows: []
      Energy:
        id: 'energy'
        htitle: 'Time (ticks)'
        vtitle: 'Net energy embodied by individuals'
        collector: (stats, rows) ->
          counts = Plant: 0, Herbivore: 0, Carnivore: 0
          counts[description.type] += description.hp for description in stats
          row = [ evoData.generation, counts.Plant, counts.Herbivore, counts.Carnivore ]
          rows.push row
        names: [ 'Plant', 'Herbivore', 'Carnivore' ]
        colors: [
            -> u.urThing('plant').bodyColor
            -> u.urThing('herbivore').bodyColor
            -> u.urThing('carnivore').bodyColor
          ]
        rows: []
geneChartSpec = ( type, gene, id ) ->
  title = type.charAt(0).toUpperCase() + type.substr(1)
  original = u.urThing(type).genes[gene][0]
  original = original() if typeof original == 'function'
  {
    id:       id
    type:     'interval'
    htitle:   'Time (ticks)'
    vtitle:   'Value of gene'
    original: original
    collector: (stats, rows) ->
      values = []
      values.push d.genes[gene] for d in stats when d.type == title
      [ min, max, mean, median ] = [ 0, 0, 0, 0 ]
      if values.length
        values.sort (a,b) -> a - b
        min = values[0]
        max = values[ values.length - 1 ]
        mean += v for v in values
        mean /= values.length
        if values.length % 2
          median = values[ Math.floor(values.length/2) ]
        else
          i = values.length / 2
          median = ( values[i] + values[i - 1] ) / 2
        rows.push [ evoData.generation, trimNum(median), trimNum(mean), trimNum(min), trimNum(max) ]
    rows: []
  }
collectData = (u) ->
  evoData.generation += 1
  byId('ticks').innerHTML = intFormat evoData.generation
  byId('created').innerHTML = intFormat u.thingsCreated()
  byId('current').innerHTML = intFormat u.currentThings()
  byId('plant-count').innerHTML = intFormat u.plantCount()
  byId('animal-count').innerHTML = intFormat u.animalCount()
  byId('herbivore-count').innerHTML = intFormat u.herbivoreCount()
  byId('carnivore-count').innerHTML = intFormat u.carnivoreCount()
  stats = u.describe()
  for tab, specs of evoData.charts
    for title, details of specs
      details.collector stats, details.rows
  if u.done && loaded
    drawChart e.innerHTML for e in sibs
  else if makeCharts
    drawChart()
window.start = ->
  if u
    u.stop()
    evoData.generation = 0
    clearCharts()
    u.erase()
  else
    byId('stop').style.display = 'inline'
    byId('start').innerHTML = 'restart'
  makeUniverse()
  u.run()
  byId('stop').innerHTML = 'stop'
window.stop = ->
  return unless u
  element = byId 'stop'
  if u.running
    u.stop()
    element.innerHTML = 'resume'
  else
    u.run()
    element.innerHTML = 'stop'
trimData = (data, size) ->
  return data if data.length < size
  results = []
  results.push data[i] for i in [data.length - size...data.length]
  results
clearCharts = ->
  resetNum = evoData.resetNum++
  for type, subtype of evoData.charts
    for title, specs of subtype
      id = specs.id
      if chart = specs.chart
        chart.clearChart()
        specs.chart = null
        specs.rows = []
      e = byId id
      id.replace /\d+$/, ''
      id = specs.id = "#{id}#{resetNum}"
      div = create 'div', 'chart'
      div.id = id
      e.parentNode.replaceChild div, e
drawChart = (ct=chartType)->
  return if ct == 'options'
  for title, specs of evoData.charts[ct] || {}
    rows = trimData specs.rows, 2000
    return unless rows.length && rows[0].length
    id     = specs.id
    chart  = specs.chart
    htitle = specs.htitle
    vtitle = specs.vtitle
    width  = specs.width || 1000
    height = specs.height || 400
    data = new google.visualization.DataTable()
    data.addColumn 'number', 'X'
    options =
      title: titlize decamelize(title)
      width: width
      explorer:
        axis: 'horizontal'
        keepInBounds: true
      height: height
      hAxis:
        title: htitle
        viewWindow:
          min: Math.max 1, rows.length - 400
          max: rows.length
      vAxis:
        title: vtitle
    if specs.type == 'interval'
      data.addColumn 'number', 'values'
      if specs.original?
        delta = rows[ rows.length - 1 ][1] - specs.original
        options.title += " (delta: #{trimNum delta})"
      ids = []
      for i in [2...5]
        data.addColumn id: "i#{i}", type: 'number', role: 'interval'
      options.interval =
            i2: style: 'line', color:'green' # mean
            i3: style: 'line', color:'black' # min
            i4: style: 'line', color:'red' # max
      options.lineWidth = 2
      options.legend    = 'none'
    else
      names  = specs.names
      colors = specs.colors
      if colors
        for c, i in colors
          colors[i] = c() if typeof c == 'function'
        options.colors = colors
      data.addColumn 'number', n for n in names
    data.addRows rows
    if chart
      chart.clearChart()
    else
      specs.chart = chart = new google.visualization.LineChart byId(id)
    chart.draw data, options
tabs = []
sibs = []
restoreOptions = ( ->
  t = byId 'tabs'
  c = t.firstChild
  while c = c.nextSibling
    break if c.innerHTML == 'options'
  -> tabClicked(c)
  )()
tabClicked = (c) ->
  return if c.className == 'active'
  s.removeAttribute 'class' for s in sibs
  c.setAttribute 'class', 'active'
  t.style.display = 'none' for t in tabs
  chartType = c.innerHTML
  if chartType == 'options'
    makeCharts = false
    byId('options').style.display = 'table'
  else
    byId( chartType + '-chart' ).style.display = 'block'
    try
      makeCharts = true
      unless loaded
        google.load 'visualization', '1', packages: ['corechart']
        google.setOnLoadCallback drawChart
        loaded = true
    catch e
      alert "Could not make charts: #{e}"
      makeCharts = false
      loaded = false
      restoreOptions()
( ->
  makeInputs()
  div = byId 'tab-div'
  while div = div.nextSibling
    tabs.push div if div.nodeType == 1
  child = byId('tabs').firstChild
  while child = child.nextSibling
    if child.nodeType == 1 && child.className != 'buffer'
      sibs.push child
      child.onclick = ( (c) -> 
        -> tabClicked c
        )(child)
)()
