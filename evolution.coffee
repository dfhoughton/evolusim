# claim namespace
window.dfh ?= {}

# constants
PI  = Math.PI
QT  = PI / 2
TAU = PI * 2

# import some functions
abs    = Math.abs
acos   = Math.acos
cos    = Math.cos
floor  = Math.floor
max    = Math.max
min    = Math.min
random = Math.random
round  = Math.round
sin    = Math.sin
sqrt   = Math.sqrt

# general handle on everything; keeps track of geometry of entities it contains
# this is the only thing added to the dfh namespace
dfh.Universe = class Universe
  # default initialization parameters
  defaults: ->
    torus: true
    width:  500
    height: 500
    cell:   20
    pause:  10
    maxDistance: 60
    initialCreatures:
      stones: num: 40
      plants: num: 60
      herbivores: num: 8
      carnivores: num: 14
  # set the universe
  constructor: ( id, options = {} ) ->
    @canvas = document.getElementById id
    throw "I have no canvas!" unless @canvas
    @ctx = @canvas.getContext '2d'
    @options     = options # keeping this around for some reason; probably unnecessary
    @width       = @canvas.width
    @height      = @canvas.height
    @maxDim      = max @width, @height
    @maxDistance = options.maxDistance || round( max( @width, @height ) / 3 )
    @torus       = options.torus
    @torus      ?= @defaults().torus

    # divide the universe into cells
    @cellWidth = options.cell || @defaults().cell
    @cells = []
    cellBuffer = []
    x = 0
    while x <= @width
      y = 0
      @cells.push column = []
      while y <= @height
        c = new Cell @, x, y, @cellWidth
        o.introduce c for o in cellBuffer
        cellBuffer.push c
        column.push c
        y += @cellWidth
      x += @cellWidth

    @thingCount = 0
    @geoPool = [ 0 ]
    @geoData = [ null ]
    @dotCache = {}
    @idBase = 0
    @tick   = 0
    @pause = options.pause || defaults().pause 
    @callback = options.callback || ->
    dic = @defaults().initialCreatures
    ic = @options.initialCreatures || dic
    uni = @
    used = {}

    # geometry mechanism
    @geo = {
      # memory allocator
      data: =>
        if @geoPool.length > 1
          offset = @geoPool.pop()
        else
          offset = @geoData.length
          @geoData.push null for i in [1..4]
        offset
      # free memory -- useful for debugging
      free: (offset) =>
        @geoPool.push offset
      calc: ( offset, x, y, maxDistance, distance ) =>
        if distance?
          sine = x
          cosine = y
        else
          unless tooFar = abs(x) > maxDistance || abs(y) > maxDistance
            distance = sqrt( x * x + y * y )
            unless tooFar ||= distance > maxDistance
              sine = y / distance
              cosine = x / distance
        unless tooFar
          segment = if sine == 0
            if cosine == 1 then 0 else 4
          else if sine == 1
            2
          else if sine == -1
            6
          else if sine > 0
            if cosine > 0 then 1 else 3
          else
            if cosine > 0 then 7 else 5
        if tooFar
          @geoPool.push offset
          0
        else
          gd = @geoData
          gd[ offset ]     = distance
          gd[ offset + 1 ] = sine
          gd[ offset + 2 ] = cosine
          gd[ offset + 3 ] = floor segment / 2   # convert the segment into a quadrant
          offset
      # produces a vector in the TrigPair direction with the given magnitude
      vector: ( offset, magnitude ) =>
        [ @geoData[ offset + 2 ] * magnitude, @geoData[ offset + 1 ] * magnitude ]
      # generates the counterpart of @ TrigPair after a 180 degree rotation
      opposite: ( offset ) =>
        return offset unless offset
        op = @geo.data()
        gd = @geoData
        gd[op]       =  gd[offset]
        gd[ op + 1 ] = -gd[offset + 1]
        gd[ op + 2 ] = -gd[offset + 2]
        gd[ op + 3 ] = ( gd[ offset + 3 ] + 2 ) % 4
        op
    }

    paramsForType = ( type, dontAdd ) ->
      params = dup( ic[type] || {} )['init'] || {}
      params.universe = uni
      params.dontAdd = dontAdd
      params
    createCreatures = ( Cons, type ) ->
      cons = -> new Cons uni.randomLocation(used), paramsForType(type)
      lim = ic[type] && ic[type].num
      lim = dic[type].num unless lim?
      cons() for i in [1..lim] if lim
    createCreatures Stone, 'stones'
    createCreatures Plant, 'plants'
    createCreatures Herbivore, 'herbivores'
    createCreatures Carnivore, 'carnivores'
    # keep an inert instance of each type in its initial state
    @seeds =
      stone:     new Stone [0,0], paramsForType( 'stones', true )
      plant:     new Plant [0,0], paramsForType( 'plants', true )
      herbivore: new Herbivore [0,0], paramsForType( 'herbivores', true )
      carnivore: new Carnivore [0,0], paramsForType( 'carnivores', true )
    @topic = null        # organism for which nearby things are outlined
    @outline = 'yellow'  # color of things outlined around topic
    # various other instance variables
    @mxd = @fiddled = @change = @running = @started = @goTime = @done = @dead = @timer = null

  # stamps out a png image representing a particular thing
  imageFor: (type) ->
    if instance = @seeds[type]
      [ width, height, x, y ] = instance.geometry()
      c = document.createElement 'canvas'
      c.setAttribute 'width', width
      c.setAttribute 'height', height
      oldX       = instance.x
      oldY       = instance.y
      oldContext = instance.context
      oldAngle   = instance.angle
      instance.x       = x
      instance.y       = y
      instance.context = c.getContext '2d'
      instance.angle   = PI * 1.5 # heading up
      instance.draw()
      instance.x       = oldX
      instance.y       = oldY
      instance.context = oldContext
      instance.angle   = oldAngle
      [ c.toDataURL( 'image/png', 1.0 ), width, height, x, y ]
  # obtains the maximum radius of any thing in the universe
  maxRadius: ->
    return @mxr if @mxr?
    mx = 0
    for t, o of @seeds
      mx = o.radius if o.radius > mx
    @mxr = mx
  maxDimensions: ->
    return @mxd if @mxd?
    h = w = 0
    for t, o of @seeds
      [ width, height ] = o.geometry()
      w = width if width > w
      h = height if height > h
    @mxd = [ w, h ]
  # iterate over all things in the universe
  visitThings: ( f, returns, safe ) ->
    ret = [] if returns
    for column in @cells
      for cell in column
        if cell.inhabitants.length
          ar = if safe then cell.inhabitants else [].concat cell.inhabitants
          for t in ar
            v = f(t)
            ret.push v if returns
    ret
  # remove all things
  clearThings: ->
    @visitThings (t) => @remThing t
    @idBase = 0
  zap: ( x, y, f=( -> true )) ->
    changed = false
    for t in @thingsAt( x, y ) when f(t)
      t.dead = true
      @remThing t
      changed = true
    setTimeout( ( => @draw() ), 0 ) if changed
  # given an organism a disease
  infect: ( x, y, virulence, mortalityRate, cureRate, factor, color, type=Animal ) ->
    for t in @thingsAt( x, y ) when t instanceof Organism and t instanceof type
      disease = new Disease virulence, mortalityRate, cureRate, factor, color
      t.sickness = count: 0, disease: disease
      t.draw()
  # set topical organism
  setTopic: ( x, y ) ->
    candidates = ( t for t in @thingsAt( x, y ) when t instanceof Animal )
    if candidates.length
      if @topic
        @highlightTopic false
        @topic.topicColor = null
      @topic             = candidates[0]
      @topic.topicColor  = @outline
      @topic.inheritMark = false
      @draw()
  # highlight an organism by coloring its belly
  highlight: ( x, y, color, inherit ) ->
    for t in @thingsAt( x, y ) when t instanceof Organism
      t.mark        = color
      t.inheritMark = inherit
      t.draw()
  # remove all highlights
  clearHighlights: ->
    @visitThings(
      (t) -> t.belly = 'white' if t instanceof Organism
      false
      true
    )
  # find all things overlapping (minus appendages) overlapping a given point
  # sorted nearest to farthest
  thingsAt: ( x, y ) ->
    c = @cellAt( x, y )
    ar = []
    f = (t) ->
      d = sqrt( (t.x - x)**2 + (t.y - y )**2 )
      ar.push [ t, d ] if d < t.radius
    f(t) for t in c.inhabitants
    for other in c.neighbors when other[1] <= @maxRadius()
      f(t) for t in other[0].inhabitants
    i[0] for i in ar.sort (a,b) -> a[1] - b[1]
  cellAt: ( x, y ) ->
    x = 0 unless x >= 0
    y = 0 unless y >= 0
    w = @cellWidth
    until cell
      column = @cells[ div x, w ]
      unless column
        x--
        continue
      cell = column[ div y, w ]
      y--
    cell
  # place a thing in the appropriate cell
  place: (thing) ->
    cell = @cellAt thing.x, thing.y
    thing.cell = cell
    cell.inhabitants.push thing
  # fetch the initial version of a particular type of organism
  urThing: (type) -> @seeds[type.toLowerCase()]
  # whether the universe consists only of things deliberately added
  fiddledWith: -> @fiddled
  addInstance: ( type, x, y ) ->
    unless @started or @fiddled
      @fiddled = true
      @clearThings()
    c = @seeds[type].clone( x, y )
    c.draw()
  addThing: (thing) ->
    thing.id = @idBase += 1
    @thingCount++
    @place thing
  remThing: (thing) ->
    thing.dead = true
    @change = true
    @topic = null if thing == @topic
    thing.cell.rem thing
    @thingCount--
    for v in ( thing.marges || [] )
      @geoPool.push v
    for k, v of thing.others when v
      @geoPool.push v
    @visitThings(
      (t) =>
        v = t.others[thing.id]
        if v?
          @geoPool.push v if v
          delete t.others[thing.id]
      false, true
    )
  # moves a thing based on that things velocity, handling reflection off
  # the edges of the universe, or wrapping the universe if it is toroidal
  moveThing: (thing) ->
    [ vx, vy ] = thing.velocity 
    return unless vx || vy
    @change = true
    thing.x += vx
    thing.y += vy
    t = @torus
    w = @width
    h = @height
    if thing.x < 0
      if t
        thing.x += w
      else
        thing.x *= -1
        vx = thing.velocity[0] *= -1
    else if thing.x > w
      if t
        thing.x -= w
      else
        thing.x -= thing.x - w
        vx = thing.velocity[0] *= -1
    if thing.y < 0
      if t
        thing.y += h
      else
        thing.y *= -1
        vy = thing.velocity[1] *= -1
    else if thing.y > h
      if t
        thing.y -= h
      else
        thing.y -= thing.y - h
        vy = thing.velocity[1] *= -1
    thing.cell.move thing
    return unless thing.angle?
    theta = anglify vx, vy
    thing.angle = theta + thing.jitter()
    if thing.marges
      thing.marges.pop() if thing.marges.length
      while thing.marges.length
        @geoPool.push thing.marges.pop()
  # chooses a random location which does not currently contain anything
  randomLocation: (used) ->
    h = @height
    w = @width
    randY = shuffle [0...h]
    for x in shuffle [0...w]
      ys = used[x] ?= []
      for y in randY
        continue if ys[y]
        ys[y] = true
        return [ x, y ]
    throw 'Universe used up!'
  # start the universe going
  run: ->
    @running = @started = true
    @go()
  thingsCreated: -> @idBase
  currentThings: -> @thingCount
  countThing: (type) ->
    count = 0
    @visitThings(
      (t) -> count++ if t instanceof type
      false, true
    )
    count
  plantCount: -> @countThing Plant
  animalCount: -> @countThing Animal
  herbivoreCount: -> @countThing Herbivore
  carnivoreCount: -> @countThing Carnivore
  tp: ( x, y, maxDistance, distance ) ->
    p = @geo.data()
    @geo.calc( p, x, y, maxDistance, distance )
  # calculate and store the geometric relationship between two things
  # returns the offset necessary to fetch this information
  # last two parameters are used in a toroidal universe to handle wrapping around the torus
  trig: ( t, o, x, y ) ->
    base = o.x - t.x + x
    height = o.y - t.y + y
    ti = t.id
    oi = o.id
    t1 = t.others[oi]
    @geoPool.push t1 if t1
    tp = @tp(base, height, @maxDistance)
    t.others[oi] = tp
    if o instanceof Animal
      t2 = o.others[ti]
      @geoPool.push t2 if t2
      o.others[ti] = @geo.opposite(tp)
    tp
  # finds the things within a particular distance of a reference thing and within a certain
  # wedge around the direction of the things movement
  # if the thing has a visual angle of 1, or the thing is motionless, all things within the distance are returned
  near: (thing, distance, angle, seen={}, candidates) ->
    nearOnes = []
    tid     = thing.id
    gd      = @geoData
    others  = thing.others
    if angle == 1
      for t in candidates
        id = t.id
        continue if t.id == tid || seen[id]
        data = others[id]
        continue unless data
        if gd[data] <= distance
          seen[id] = true
          nearOnes.push t
    else
      [ t1, t2, d ] = thing.margins()
      sin1 = gd[ t1 + 1 ]
      qdr1 = gd[ t1 + 3 ]
      sin2 = gd[ t2 + 1 ]
      qdr2 = gd[ t2 + 3 ]
      if d
        q1 = 0
        q2 = ( qdr2 + d ) % 4
      else
        q1 = qdr1
        q2 = qdr2
      for t in candidates
        id = t.id
        continue if id == tid || seen[id]
        tp = others[id]
        continue unless tp
        d3 = gd[tp]
        continue unless d3 and d3 <= distance
        qdr3 = gd[ tp + 3 ]
        q3 = if d then ( qdr3 + d ) % 4 else qdr3
        if q1 <= q3 <= q2
          if q1 < q3 < q2
            nearOnes.push t
          else
            sin3 = gd[ tp + 1 ]
            risingSine = qdr3 == 0 or qdr3 == 3
            keep = if qdr1 == qdr2
              if risingSine
                sin1 <= sin3 <= sin2
              else
                sin1 >= sin3 >= sin2
            else
              if qdr3 == qdr1
                if risingSine
                  sin1 <= sin3
                else
                  sin1 >= sin3
              else
                if risingSine
                  sin2 >= sin3
                else
                  sin2 <= sin3
            nearOnes.push t if keep
    nearOnes
  # calculate part of the boundary of a dot
  topLeftArc: (radius) ->
    boundary = []
    candidatePoint = [ 0, -radius ]
    test = (pt) ->
      [ x, y ] = pt
      r = radius + y
      sqrt( x * x + r * r ) <= radius
    boundary.push [].concat(candidatePoint) if test(candidatePoint)
    while ((candidatePoint[1] += 1) <= 0)
      while true
        candidatePoint[0] -= 1
        unless test candidatePoint
          candidatePoint[0] += 1
          boundary.push [ candidatePoint[0], candidatePoint[1] ]
          break
    boundary
  # make a collection of points fitting inside the given radius
  dot: (radius) ->
    radius = round radius
    @dotCache[radius] ?= ( =>
      boundary = @topLeftArc radius
      points = []
      cherry = boundary.shift() if boundary[0][0] == 0
      # mirror left and right
      boundary = map boundary, (p) -> [ p, [ -p[0], p[1] ] ]
      # mirror top and bottom
      for i in [(boundary.length - 2)..0]
        [ p1, p2 ] = boundary[i]
        y = -p1[1]
        boundary.push [ [ p1[0], y ], [ p2[0], y ] ]
      # convert each pair of boundary points into a row of boundary and interior points
      for row in boundary
        [ p1, p2 ] = row
        points.push p1
        for i in [( p1[0] + 1 )...p2[0]]
          points.push [ i, p1[1] ]
        points.push p2
      if cherry
        points.unshift cherry
        points.push [ 0, radius ]
      points
    )()
  # collects the points in the universe within radius of (x,y)
  pointsNear: (x, y, radius) ->
    x = round x
    y = round y
    points = map @dot(radius), (p) -> [ p[0] + x, p[1] + y ]
    w = @width
    h = @height
    if x - radius < 0 || x + radius >= w || y - radius < 0 || y + radius >= h
      grep points, (p) -> 0 <= p[0] < w && 0 <= p[1] < h
    else
      points
  # the steps involved in one go of the universe's clock
  go: ->
    @goTime  = new Date()
    @timer ?= @goTime
    @change  = false
    @tick   += 1
    @visitThings(
      (t) -> t.clean()
      false, true
    )
    @move()
    self = @
    setTimeout(
      ->
        self.die()
        setTimeout(
          ->
            self.cure()
            setTimeout(
              ->
                self.babies()
                self.done = self.dead || !self.change
                setTimeout(
                  ->
                    self.draw()
                    setTimeout(
                      ->
                        self.callback(self)
                        if self.running && !self.done
                          pause = self.pause - new Date().getTime() + self.goTime.getTime()
                          pause = 0 if pause < 0;
                          setTimeout(
                            -> self.go()
                            pause
                          )
                      0
                    )
                  0
                )
              0
            )
          0
        )
      0
    )
  # restore various booleans so a dead universe can be restarted
  prime: ->
    @running = @done = @dead = false
  # give every organism an opportunity to heal from any disease
  cure: ->
    @visitThings(
      (t) -> t.cure() if t instanceof Organism
      false
      true
    )
  # give every organism an opportunity to eat or starve
  # returns whether any organisms remain alive
  die: ->
    mortal = []
    @visitThings (t) ->
      return if t.dead
      mortal.push t if t.type and t instanceof Organism
    for t in shuffle mortal
      switch t.type
        when Herbivore
          for other in t.touching()
            break if t.full()
            t.eat other if other instanceof Plant
        when Carnivore
          for other in t.touching()
            break if t.full()
            t.eat other if other instanceof Herbivore
      if t instanceof Animal and t.hp <= 0 or t.succumbs()
        @remThing t
      else if t.isSick()
        t.expose other for other in t.touching() when other.type? and other.type == t.type
    @dead = true
    for t in mortal
      unless t.dead
        @dead = false
        break
    @dead
  # set temporary outlines
  highlightTopic: (turnOn=true) ->
    if @topic
      others = @topic.nearby()
      if turnOn
        color = @outline || 'yellow'
        other.outline color for other in others
      else
        other.outlined = false for other in others
  # paint a moment in time
  draw: ->
    @erase()
    @highlightTopic()
    for type in [ Stone, Plant, Herbivore, Carnivore]
      @visitThings(
        (t) -> t.draw() if t instanceof type
        false, true
      )
    @topic.draw() if @topic  # redraw topic on top of anything with which it overlaps
  # make all the current things react appropriately to the last moment in time
  move: ->
    @visitThings (t) -> t.react()
    @visitThings (t) =>
      @moveThing t if t instanceof Animal
    true
  # all surviving things that are able to reproduce
  makeCradles: ->
    column = map [0...@height], -> true
    map [0...@width], -> [].concat column
  babies: ->
    cradles = @makeCradles()
    orchards = @makeCradles()
    organisms = []
    @visitThings(
      (t) =>
        points = @pointsNear t.x, t.y, t.radius * 2
        organisms.push t if t instanceof Organism
        @removeCradles cradles, points unless t instanceof Plant
        @removeCradles orchards, points unless t instanceof Stone
      false, true
    )
    for t in shuffle organisms
      c = if t instanceof Plant then orchards else cradles
      t.reproduce c
  findCradles: (allCradles, newCradles) ->
    grep newCradles, (pt) -> allCradles[pt[0]][pt[1]]
  removeCradles: (allCradles, points) ->
    for pt in points
      col = allCradles[pt[0]]
      col[pt[1]] = false if col
  # stop the universe
  stop: -> @running = false
  start: -> @run() if !@running
  # blank out the universe prior to redrawing everything
  erase: ->
    if @options.erase then @options.erase() else
      c = @canvas
      @ctx.clearRect 0, 0, c.width, c.height
  describe: ->
    @visitThings(
      (t) -> t.describe()
      true, true
    )

  # debugging/development utility methods

  # profiling utility
  time: ( obj, name, time ) ->
    now = new Date()
    obj[name] = now.getTime() - time.getTime()
    now
  reportDelta: (name) ->
    now = new Date()
    delta = now.getTime() - @timer.getTime()
    @timer = now
    console.log name, delta
  countTypes: ->
    counts = {}
    names = {}
    @visitThings(
      (t) ->
        n = names[t.type] ?= t.typeName()
        counts[n] ?= 0
        counts[n] += 1
      false, true
    )
    all = ( "#{t}: #{c}" for t, c of counts ).sort().join ', '
    console.log all
  # introspection mechanism
  getType: (type) ->
    return type unless typeof type == 'string'
    switch type
      when 'Thing' then Thing
      when 'Stone' then Stone
      when 'Organism' then Organism
      when 'Plant' then Plant
      when 'Animal' then Animal
      when 'Herbivore' then Herbivore
      when 'Carnivore' then Carnivore
  getThings: (type) ->
    type = @getType type
    ret = []
    @visitThings(
      (t) -> ret.push t if t instanceof type
      false, true
    )
  # debugging method
  pickThing: (type) ->
    type = @getType type
    rightThings = @getThings type
    rightThings[ ~~( random() * rightThings.length )]

# converts a vector to its angle
# solves problem introduced by angle normalization
anglify = (x, y) ->
  a = abs x
  h = sqrt( x*x + y*y )
  theta = acos( a / h )
  if x < 0
    if y < 0 then PI + theta else PI - theta
  else
    if y < 0 then 2 * PI - theta else theta

grep = ( ar, f ) ->
  x for x in ar when f(x)

map = ( ar, f ) ->
  f(x) for x in ar

dup = (obj) ->
  return null unless obj?
  if ( obj instanceof Array )
    map obj, (o) -> dup o
  else if ( typeof obj == 'object' )
    copy = {}
    copy[k] = dup v for k, v of obj
    copy
  else
    obj

degrees = (radians) -> 360 * radians / TAU

div = ( n, d ) -> floor n / d

# randomization utility
shuffle = (ar, dup=false) ->
  ar = [].concat ar if dup
  i = ar.length
  while --i
    j = ~~( random() * ( i + 1 ) )
    t = ar[i]
    ar[i] = ar[j]
    ar[j] = t
  ar

# a division of the universe that knows its neighborhood
class Cell
  constructor: ( universe, x, y, width ) ->
    @universe    = universe
    @x           = x
    @y           = y
    @farX        = min( x + width, universe.width )
    @farY        = min( y + width, universe.height )
    @width       = width
    @neighbors   = []
    @inhabitants = []
  # whether this cell is the appropriate container for the thing
  has: (thing) ->
    @x <= thing.x < @farX && @y <= thing.y < @farY
  # shift the thing to another cell as appropriate
  move: (thing) ->
    unless @has thing
      @rem thing
      @universe.place thing
  # remove the thing from this cell's purview
  rem: (thing) ->
    for t, i in @inhabitants
      if t == thing
        @inhabitants.splice i, 1
        break
  # the minimum distance between a point in one cell and a point in the other
  # and whether this distance involves wrapping in the horizontal or vertical dimensions
  distance: (other) ->
    t  = @universe.torus
    w  = @universe.width
    h  = @universe.height
    wx = 0
    wy = 0
    if @x < other.x
      if t
        if other.x - @farX > w / 2
          x1 = @x
          x2 = other.farX - w
          wx = -w
        else
          x1 = @farX
          x2 = other.x
      else
        x1 = @farX
        x2 = other.x
    else if @x > other.x
      if t
        if @x - other.farX > w / 2
          x1 = @farX
          x2 = other.x + w
          wx = w
        else
          x1 = @x
          x2 = other.farX
      else
        x1 = @x
        x2 = other.farX
    else
      x1 = x2 = 0
    if @y < other.y
      if t
        if other.y - @farY > h / 2
          y1 = @y
          y2 = other.farY - h
          wy = -h
        else
          y1 = @farY
          y2 = other.y
      else
        y1 = @farY
        y2 = other.y
    else if @y > other.y
      if t
        if other.farY - @y > h / 2
          y1 = @farY
          y2 = other.y + h
          wy = h
        else
          y1 = @y
          y2 = other.farY
      else
        y1 = @y
        y2 = other.farY
    else
      y1 = y2 = 0
    x = x1 - x2
    y = y1 - y2
    [ sqrt( x * x + y * y ), wx, wy ]
  # introduce potentially neighboring cells to each other
  introduce: ( other, maxDistance=@universe.maxDistance ) ->
    [ d, wx, wy ] = @distance other
    if d <= maxDistance
      @neighbors.push [ other, d, wx, wy ]
      other.neighbors.push [ @, d, -wx, -wy ]
  # collect a candidate set of things potentially within the given radius of the thing
  # thing should be an inhabitant of this cell
  near: ( thing, distance=@universe.maxDistance ) ->
    ret = []
    for t in @inhabitants when t != thing
      ret.push t
      thing.others[t.id] ?= @universe.trig thing, t, 0, 0
    for n in @neighbors when n[1] <= distance
      [ o, _, wx, wy ] = n
      for t in o.inhabitants
        ret.push t
        thing.others[t.id] ?= @universe.trig thing, t, wx, wy
    ret
  # debugging methods
  drawRadius: (radius, inhabitants=true) ->
    n[0].draw 'grey', inhabitants for n in @neighbors when n[1] <= radius
    @draw 'black'
  draw: (color='grey', inhabitants=true) ->
    @outline(color)
    @showInhabitants() if inhabitants
  outline: (color='grey') ->
    ctx = @universe.ctx
    ctx.rect @x, @y, @width, @width
    ctx.strokeStyle = color
    ctx.stroke()
  showInhabitants: ->
    color = @universe.outline
    for t in @inhabitants
      t.outline color
      t.draw()

# something in the universe
class Thing
  constructor: ( location, options = {} ) ->
    throw "I need a universe!" unless options.universe
    @setAttributes options
    [ @x, @y ] = location
    @velocity  = [ 0, 0 ]
    @radius   ?= 5
    @type      = Thing
    @others    = {}
    @outlined  = false
    @marges    = null
    unless @dontAdd
      uni = @universe
      uni.change = true
      uni.addThing @
  # makes a clone of the thing and places it in the universe
  clone: ( x, y ) ->
    type = @universe.getType @typeName()
    c = new type( [x, y], universe: @universe )
    for k, v of @ when not /^(?:universe|dontAdd|others|angle|x|y)$/.test k
      c[k] = dup(v)
    c.angle = random() * TAU if @angle?
    c
  typeName: ->
    s = "" + @type
    s = s.substr 0, s.indexOf '('
    s.replace /^.*?([A-Z]\w+).*/, '$1'
  describe: ->
    {
      x: @x
      y: @y
      velocity: @velocity
      type: @typeName()
    }
  react: ->
  jitter: -> 0
  stationary: -> !( @velocity[0] || @velocity[1] )
  move: ->
  ctx: -> @context ?= @universe.ctx
  draw: (color=@bodyColor) -> @drawBody(color)   # color param is useful during debugging
  outline: (color) -> @outlined = color
  drawBody: (color=@bodyColor) ->
    if @outlined
      @drawCircle(
        @x
        @y
        @radius + 2
        @outlined
      )
      @outlined = false
    @drawCircle(
      @x
      @y
      @radius
      color || 'black'
    )
  drag: ->
  drawCircle: ( x, y, radius, color ) -> @drawArc x, y, radius, color, 0, TAU
  drawArc: ( x, y, radius, color, start, end ) ->
    return unless radius > 0
    ctx = @ctx()
    ctx.beginPath()
    ctx.arc x, y, radius, start, end
    ctx.fillStyle = color
    ctx.fill()
  setAttributes: ( options = {} ) ->
    for key, value of options
      do => @[key] = value
  # all the things whose center is within the radius of @ thing
  touching: ->
    candidates = @cell.near @, @radius
    @universe.near @, @radius, 1, {}, candidates
  margins: ->
    m = @marges ?= []
    return m if m.length
    fi = PI * @visualAngle()
    gd = @universe.geoData
    t1 = @angle - fi
    t1 = @universe.tp sin(t1), cos(t1), null, true
    q1 = gd[ t1 + 3 ]
    t2 = @angle + fi
    t2 = @universe.tp sin(t2), cos(t2), null, true
    q2 = gd[ t2 + 3 ]
    m.push t1
    m.push t2
    m.push if q1 > q2 then 4 - q1 else 0  # an adjustment factor to make it easier to compare quadrants
    m
  clean: ->
    for k, v of @others
      @universe.geoPool.push v if v
      delete @others[k]
    if @marges
      while @marges.length
        @universe.geoPool.push @marges.pop()
  healthRatio: -> 1
  # returns the outer dimentions of a box sufficient to hold a vertically oriented thing
  # and the point that is the thing's apparent center
  geometry: ->
    width = 2 * @radius
    [ width, width, @radius, @radius ]
  # debugging methods
  # distance
  dist: (t) ->
    x = @x - t.x
    y = @y - t.y
    sqrt x*x + y*y
  # the angle in radians, measuring clockwise from 3 o'clock, facing t from this
  absAngle: (t) ->
    isAbove = @y < t.y
    isBefore = @x < t.x
    if @x == t.x
      return if isAbove then QT else 3 * QT
    if @y == t.y
      return if isBefore then 0 else PI
    theta = degrees acos abs( @x - t.x ) / @dist(t)
    if isAbove
      if isBefore then theta else 180 - theta
    else
      if isBefore then 360 - theta else 180 + theta
  relativeGeometry: (t) ->
    offset = @others[t.id]
    if offset
      distance:  @universe.geoData[offset]
      sine:      @universe.geoData[offset + 1]
      cosine:    @universe.geoData[offset + 2]
      quadrant:  @universe.geoData[offset + 3]
    else
      'beyond maximum distance considered'

class Stone extends Thing
  constructor: ( location, options = {} ) ->
    super location, options
    @bodyColor ?= 'grey'
    @radius = options.radius || 8
    @type = Stone
  drag: -> 0

class Organism extends Thing
  constructor: ( location, options = {} ) ->
    super location, options
    @genes      ?= @defaultGenes()
    @hp         ?= @health() / 2
    @generation ?= 1
    @radius     ?= 5
    @tick        = @universe.tick
    @babies      = 0
    @mark       ?= null
    @belly      ?= 'white'
    @hr = @sickness = @topicColor = null
  describe: ->
    description = super()
    description.health = @health()
    description.hp = @hp
    description.tick = @tick
    description.babies = @babies
    genes = description.genes = {}
    for k, v of @genes
      v = v[0]
      v = if typeof v == 'function' then v(@) else v
      genes[k] = v
    description
  defaultGenes: ->
    {
      health: [ 10, 5, (t) -> 2 * t.health() ]
      babyCost: [ 1, 1, (t) -> t.health() / 2 ]
      babyThreshold: [ .5, .1, .9 ]
      babyTries: [ 2, 1, (t) -> min( 100, t.babyTries() * 2 ) ]
      mutationRate: [ .1, 0.01, 1 ]
      mutationRange: [ .1, 0.01, 1 ]
    }
  # how far away from its mother a baby can be "born"
  dispersalRadius: -> 2.5 * @radius
  # utility function for extending default genes
  mergeGenes: ( base, ext ) ->
    genes = {}
    genes[k] = v for k, v of base
    genes[k] = v for k, v of ext
    genes
  draw: (color=@bodyColor) ->
    super(color)
    @drawHunger()
  drawHunger: -> # show emptiness of belly
    h = @health()
    r = ( @radius - 1 ) * ( h - @hp ) / h
    color = @topicColor || @mark || @belly
    @drawCircle @x, @y, r, color
    if @sickness?
      @drawCircle @x, @y, 3 * r / 4, @sickness.disease.color
  # maximum health points an organism can retain
  health: -> @genes.health[0]
  # amount of health one loses per round
  need: -> 0
  # how much you get for free per round
  gain: -> 0
  react: ->
    start = @hp
    @hp += @gain()
    @hp -= @need()
    @hp = min @hp, @health()
    @universe.change = true if start != @hp
  # number of times per baby that one can attempt to find it a cradle
  babyTries: -> @genes.babyTries[0]
  # number of health points to transfer to baby
  babyCost: -> @genes.babyCost[0]
  # minimum fraction of one's total health one must retain after making a baby
  babyThreshold: -> @genes.babyThreshold[0]
  # the number of babies an organism gives birth to in a turn
  numBabies: ->
    numerator = @hp - @health() * @babyThreshold()
    denominator = @babyCost() + 1
    ~~(  numerator / denominator )
  # duplicate genes, perhaps with mutation, for baby
  mitosis: ->
    genes = {}
    mrate = @genes.mutationRate[0]
    mrange = @genes.mutationRange[0]
    for k, v of @genes
      [ value, mn, mx ] = v
      if random() <= mrate # mutation!
        mi = if typeof mn == 'function' then mn(@) else mn
        ma = if typeof mx == 'function' then mx(@) else mx
        delta = random() * mrange * ( ma - mi )
        delta *= -1 if random() > .5
        value += delta
        value = max( mi, min( ma, value ) )
      genes[k] = [ value, mn, mx ]
    genes
  # choose a pace to try to place a baby
  babyPoint: ->
    length = 2 * @radius + random() * ( @dispersalRadius() - 2 * @radius )
    angle = random() * TAU
    x = round( @x + length * cos angle )
    y = round( @y + length * sin angle )
    # bounce points outside universe back in
    if x < 0
      x *= -1
    else if x > @universe.width
      x = 2 * @universe.width - x
    else if x == @universe.width
      x -= 1
    if y < 0
      y *= -1
    else if y > @universe.height
      y = 2 * @universe.height - y
    else
      y -= 1
    [ x, y ]
  reproduce: (cradles) ->
    if ( n = @numBabies() ) > 0
      # put babies in cradles
      for i in [1..n]
        for i in [1..@babyTries()]
          pt = @babyPoint()
          column = cradles[pt[0]]
          if column and column[pt[1]]
            genes = @mitosis()
            @hp -= 1 + @babyCost()
            # put the baby in the cradle
            baby = new @type( 
              pt
              {
                universe:    @universe
                genes:       genes
                hp:          @babyCost()
                radius:      @radius
                bodyColor:   @bodyColor
                inheritMark: @inheritMark
                mark:        if @inheritMark then @mark else null
                belly:       if @inheritMark then @belly else null
                generation:  @generation + 1
              }
            )
            @babies += 1
            # clean the cradles for the next one
            @universe.removeCradles cradles, @universe.pointsNear( baby.x, baby.y, baby.radius * 2 )
            break
  clean: ->
    super()
    @hr = null
  healthRatio: ->
    @hr ?= @hp / @health()

  # disease-related methods
  # a sick organism has a "sickness", which consists of a disease object and a count
  # of ticks since the organism contracted the desease

  # determines whether the disease is fatal on a particular tick
  succumbs: ->
    if @sickness?
      @sickness.disease.fatal @, @sickness.count++
  isSick: -> @sickness? and @sickness.count
  # expose the other organism to the disease
  expose: (other) ->
    return false if other.isSick()
    if @sickness.disease.catches other
      other.sickness = count: 0, disease: @sickness.disease.spread()
      @universe.change = true
  cure: ->
    if @isSick() and @sickness.disease.cures @, @sickness.count
      @sickness = null 
      @universe.change = true

class Plant extends Organism
  constructor: ( location, options = {} ) ->
    super location, options
    @bodyColor ?= 'green'
    @radius    ?= 4
    @type       = Plant
  gain: -> .5
  defaultGenes: ->
    @mergeGenes super(), {
      dispersalRadius: [
        => @radius * 15
        (t) -> t.radius * 3
        (t) -> t.radius * 10
      ]
    }
  dispersalRadius: ->
    dr = @genes.dispersalRadius[0]
    dr = @genes.dispersalRadius[0] = dr() if typeof dr == 'function'
    dr

class Animal extends Organism
  constructor: ( location, options = {} ) ->
    super location, options
    @bodyColor ?= 'brown'
    @radius    ?= 5
    @angle      = random() * TAU   # initial orientation
    @velocity   = [ 0, 0 ]
    @type       = Animal
    @foodType = @ma = @maxSp = @tailSize = @earSize  = @eyeSize = null
  defaultGenes: ->
    @mergeGenes super(), {
      auditoryRange: [
        min( @universe.maxDistance / 3, 20 )
        10
        (t) -> 2 * t.visualRange() / 3
      ]
      visualAngle: [ .35, .1, .6 ]
      visualRange: [ min( @universe.maxDistance / 2 , 30 ), 20, @universe.maxDistance ]
      g: [ 250, 1, 5000 ]
      jitter: [ .05, 0.01, 1 ]
      kinAffinity: [
        -2
        (t) -> -max( .1, abs(t.kinAffinity()) * 2 )
        (t) -> max( .1, abs(t.kinAffinity()) * 2 )
      ]
      foodAffinity: [
        10
        (t) -> -max( .1, abs(t.foodAffinity()) * 2 )
        (t) -> max( .1, abs(t.foodAffinity()) * 2 )
      ],
      maxAcceleration : [
        => @radius / 2
        (t) -> t.radius / 4
        (t) -> t.maxSpeed() * 2
      ]
    }
  need: -> 0.1
  full: -> @hp == @health()
  eat: (other) ->
    @hp += other.hp / 2
    @hp = min( @health(), @hp ) # you can't exceed maximum health
    @universe.remThing other
  visualAngle: -> @genes.visualAngle[0]
  visualRange: -> @genes.visualRange[0]
  g: -> @genes.g[0]
  jitter: -> @genes.jitter[0]
  kinAffinity: -> @genes.kinAffinity[0]
  foodAffinity: -> @genes.foodAffinity[0]
  predatorAffinity: -> @genes.predatorAffinity[0]
  maxAcceleration: ->
    return @ma if @ma?
    @ma = if typeof @genes.maxAcceleration[0] == 'function'
      @genes.maxAcceleration[0] = @genes.maxAcceleration[0]()
    else
      @genes.maxAcceleration[0]
  maxSpeed: -> @maxSp ?= @radius * 1.5
  react: ->
    super()
    x = 0
    y = 0
    geo = @universe.geo
    g = @g()
    gd = @universe.geoData
    for other in @nearby()
      influence = @affinity other
      if influence
        data = @others[other.id]
        d = gd[data]
        continue unless d
        influence /= d * d
        influence *= g
        [ xa, ya ] = geo.vector data, influence
        x += xa
        y += ya
    if x || y
      ma = @maxAcceleration()
      m = sqrt( x * x + y * y )
      if m > ma
        f = ma / m
        x *= f
        y *= f
      [ vx, vy ] = @velocity
      vx += x
      vy += y
      m = sqrt( vx * vx + vy * vy )
      if m > @maxSpeed()
        f = @maxSpeed() / m
        vx *= f
        vy *= f
      @velocity = [ vx, vy ]  # we've adjusted the velocity, but we save the moving until all velocities are adjusted
  # influencing entities nearby
  auditoryRange: -> @genes.auditoryRange[0]
  nearby: ->
    ar = @auditoryRange()
    vr = @visualRange()
    candidates = @cell.near @, max( vr, ar )
    seen = {}
    nearby = @universe.near @, ar, 1, seen, candidates
    nearby.concat @universe.near @, vr, @visualAngle(), seen, candidates
  reactToOther: ( other, data ) ->
  prey: (other) ->
    false
  geometry: ->
    @tailSize ?= @calcTailSize()
    @earSize  ?= @calcEarSize()
    @eyeSize  ?= @calcEyeSize()
    width = 2 * ( @radius + @earSize + 2 )
    height = 2 * @radius + @tailSize + @eyeSize + 2
    x = 2 + @radius + @earSize
    y = @eyeSize / 2  + @radius
    [ width, height, x, y ]
  draw: (color=@bodyColor) ->
    super(color)
    @drawHead color
    @tailSize ?= @calcTailSize()
    @drawTail color
  # some decorations that let us see the animal's angle of vision
  # the direction of its gaze, and where it's headed
  drawHead: (color) ->
    @earSize ?= @calcEarSize()
    @drawEar false, color
    @drawEar true, color
    inc = @visualAngle() * QT
    @eyeSize ?= @calcEyeSize()
    @drawEye inc
    @drawEye -inc
  drawEar: (left, color) ->
    point = @angle + if left then -QT else QT
    rad = @earSize
    [ start, end ] = if left then [ @angle, @angle + PI ] else [ @angle - PI, @angle ]
    [ x, y ] = @edgePoint point, rad + @radius
    @drawArc x, y, rad, color, start, end
  calcTailSize: ->
    size = @radius * @maxAcceleration() / @genes.maxAcceleration[2](@)
    max 2, size
  calcEarSize: ->
    ratio = @auditoryRange() / @genes.auditoryRange[2](@)
    size = ratio * @radius / 3
    max size, 1
  calcEyeSize: ->
    ratio = @visualRange() / @genes.visualRange[2]
    size = ratio * @radius / 4
    max size, .75
  drawEye: (inc) ->
    a = @angle + inc
    [ x, y ] = @edgePoint a
    @drawCircle x, y, @eyeSize, 'black'
  drawTail: (color) ->
    a = @angle + PI
    [ x1, y1 ] = @edgePoint a
    [ x2, y2 ] = @edgePoint a, @radius + @tailSize
    c = @ctx()
    c.beginPath()
    c.moveTo x1, y1
    c.lineTo x2, y2
    c.lineWidth = 2
    c.strokeStyle = color
    c.lineCap = 'round'
    c.stroke()
  edgePoint: ( a, r = @radius ) ->
    x = @x + r * cos a
    y = @y + r * sin a
    [ x, y ]
  affinity: (other) ->
    switch other.type
      when @type then @kinAffinity()
      when @foodType
        @foodAffinity() * other.healthRatio() / @healthRatio()
      when Stone
        d = @universe.geoData[@others[other.id]]
        if d <= other.radius or d <= @radius
          @_ma ?= @maxSpeed() * 2
          -20000
        else
          -20
      else 0
  # some debugging methods
  showSeen: (color='black') ->
    @universe.draw()
    vr = @visualRange()
    candidates = @cell.near @, vr
    seen = @universe.near @, vr, @visualAngle(), null, candidates
    for t in seen
      t.outline()
      t.draw('black')
  showHeard: (color='purple') ->
    @universe.draw()
    ar = @auditoryRange()
    candidates = @cell.near @, ar
    heard = @universe.near @, ar, 1, null, candidates
    for t in heard
      t.outline()
      t.draw(color)
  relativeGeometry: (t) ->
    data = super(t)
    [ t1, t2 ] = @margins()
    data.auditoryScope = @auditoryRange()
    data.visualScope =
      range: @visualRange()
      left:
        sine:     @universe.geoData[ t1 + 1 ]
        cosine:   @universe.geoData[ t1 + 2 ]
        quadrant: @universe.geoData[ t1 + 3 ]
      right:
        sine:     @universe.geoData[ t2 + 1 ]
        cosine:   @universe.geoData[ t2 + 2 ]
        quadrant: @universe.geoData[ t2 + 3 ]
    data


class Herbivore extends Animal
  constructor: ( location, options = {} ) ->
    super location, options
    @type     = Herbivore
    @foodType = Plant
  defaultGenes: ->
    @mergeGenes super(), {
      predatorAffinity: [
        -4
        (t) -> -abs(max(1, t.predatorAffinity())) * 2
        (t) ->  abs(max(1, t.predatorAffinity())) * 2
      ]
    }
  affinity: (other) ->
    switch other.type
      when Carnivore then @predatorAffinity()
      else super other

class Carnivore extends Animal
  constructor: ( location, options = {} ) ->
    super location, options
    @bodyColor ?= 'red'
    @radius    ?= 6
    @type       = Carnivore
    @foodType   = Herbivore
  defaultGenes: ->
    @mergeGenes super(), {
      g: [ 500, 1, 5000 ]
      babyThreshold: [ .4, .1, .9 ]
      plantAffinity: [
        .1
        (t) -> -abs(max( 1, t.plantAffinity())) * 2
        (t) ->  abs(max( 1, t.plantAffinity())) * 2
      ]
    }
  plantAffinity: -> @genes.plantAffinity[0]
  affinity: (other) ->
    switch other.type
      when Plant then @plantAffinity()
      else super other

# not the fanciest disease model; adding evolutionary features would be cool
class Disease
  constructor: ( virulence, mortalityRate, cureRate, healthFactor=6, color='green' ) ->
    @virulence     = virulence
    @mortalityRate = mortalityRate
    @cureRate      = cureRate
    @color         = color
    @healthFactor  = healthFactor
    @initParams    = [ virulence, mortalityRate, cureRate ] # to facilitate more sophisticated disease models
  fatal: ( organism, count ) ->
    p = @mortalityRate - organism.healthRatio() / @healthFactor
    p > 0 and random() <= p
  catches: (organism) ->
    p = @virulence - organism.healthRatio() / @healthFactor
    p > 0 and random() <= p
  spread: -> @
  cures: ( organism, count ) ->
    p = @cureRate + organism.healthRatio() / @healthFactor
    p >= 1 or random() <= p
