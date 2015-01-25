# general handle on everything; keeps track of geometry of entities it contains
class Universe
  # default initialization parameters
  defaults: ->
    width: 500
    height: 500
    pause: 10
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
    @options = options # keeping this around for some reason; probably unnecessary
    @width = @canvas.width
    @height = @canvas.height
    @maxDim = Math.max @width, @height
    @things = []
    @geoPool = [ 0 ]
    @geoData = [ null ]
    @dotCache = {}
    @idBase = 0
    @tick   = 0
    @pause = options.pause || 0 
    @recalculateGeometries = if options.responsive then @responsiveRecalculate else @fastRecalculate
    @maxDistance = options.maxDistance || Math.round( Math.max( @width, @height ) / 3 )
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
          unless tooFar = Math.abs(x) > maxDistance || Math.abs(y) > maxDistance
            distance = Math.sqrt( Math.pow(x, 2) + Math.pow(y, 2) )
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
          @geoData[ offset ]     = distance
          @geoData[ offset + 1 ] = sine
          @geoData[ offset + 2 ] = cosine
          @geoData[ offset + 3 ] = segment
          offset
      le: ( offset, other ) =>
        s1 = @geoData[ offset + 3 ]
        s2 = @geoData[ other + 3 ]
        if s1 == s2
          if s1 % 2 == 0
            true
          else
            sine1 = @geoData[ offset + 1 ]
            sine2 = @geoData[ offset + 1 ]
            if s1 == 1 || s1 == 7 then sine1 <= sine2 else sine1 >= sine2
        else
          s1 - s2 > 4 || s1 < s2
      ge: ( offset, other ) =>
        @geo.le other, offset
      # produces a vector in the TrigPair direction with the given magnitude
      vector: ( offset, magnitude ) =>
        [ @geoData[ offset + 2 ] * magnitude, @geoData[ offset + 1 ] * magnitude ]
      # generates the counterpart of @ TrigPair after a 180 degree rotation
      opposite: ( offset ) =>
        return offset unless offset
        op = @geo.data()
        @geo.calc( op, -@geoData[ offset + 1 ], -@geoData[ offset + 2 ], null, @geoData[offset] )
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
    @seeds = {
      'plant'     : new Plant [0,0], paramsForType( 'plants', true )
      'herbivore' : new Herbivore [0,0], paramsForType( 'herbivores', true )
      'carnivore' : new Carnivore [0,0], paramsForType( 'carnivores', true )
    }

  # fetch the initial version of a particular type of organism
  urThing: (type) -> @seeds[type.toLowerCase()]
  addThing: (thing) ->
    thing.id = @idBase += 1
    @addToCollection thing, @things
  addToCollection: (thing, collection) ->
    if thing instanceof Animal
      @trig thing, t for t in collection
    else
      @trig t, thing for t in collection when t instanceof Animal
    collection.push thing
  # do all recalculations without yielding any time to browser events
  fastRecalculate: ->
    fresh = []
    setTimeout(
      =>
        t.clean() for t in @things
        @addToCollection thing, fresh for thing in @things
        @things = fresh
        @afterGeometry()
      0
    )
  # yield frequently to the browser while recalculating events
  responsiveRecalculate: ->
    fresh = []
    nextThing = =>
      if @things.length
        t = @things.shift()
        @addToCollection t, fresh
        setTimeout nextThing, 0
      else
        @things = fresh
        @afterGeometry()
    nextThing()
  remThing: (thing) ->
    thing.dead = true
    @change = true
    for v in ( thing.marges || [] )
      @geoPool.push v
    for k, v of thing.others when v
      @geoPool.push v
    for t in @things
      v = t.others[thing.id]
      if v?
        @geoPool.push v if v
        delete t.others[thing.id]
  # moves a thing based on that things velocity, handling reflection off
  # the edges of the universe
  moveThing: (thing) ->
    [ vx, vy ] = thing.velocity 
    return unless vx || vy
    @change = true
    thing.x += vx
    thing.y += vy
    if thing.x < 0
      thing.x *= -1
      vx = thing.velocity[0] *= -1
      thing.changed = true
    else if thing.x > @width
      thing.x -= thing.x - @width
      vx = thing.velocity[0] *= -1
      thing.changed = true
    if thing.y < 0
      thing.y *= -1
      vy = thing.velocity[1] *= -1
      thing.changed = true
    else if thing.y > @height
      thing.y -= thing.y - @height
      vy = thing.velocity[1] *= -1
      thing.changed = true
    return unless thing.angle?
    theta = anglify vx, vy
    thing.angle = theta + thing.jitter()
    if thing.marges
      while thing.marges.length
        @geoPool.push thing.marges.pop()
  # chooses a random location which does not currently contain anything
  randomLocation: (used) ->
    h = @height
    w = @width
    randY = shuffle [0...h]
    for x in shuffle [0...w]
      ys = used[x] ||= []
      for y in randY
        continue if ys[y]
        ys[y] = true
        return [ x, y ]
    throw 'Universe used up!'
  # start the universe going
  run: ->
    @running = true
    @go()
  thingsCreated: -> @idBase
  currentThings: -> @things.length
  countThing: (type) ->
    count = 0
    count++ for t in @things when t instanceof type
    count
  plantCount: -> @countThing Plant
  animalCount: -> @countThing Animal
  herbivoreCount: -> @countThing Herbivore
  carnivoreCount: -> @countThing Carnivore
  tp: ( x, y, maxDistance, distance ) ->
    p = @geo.data()
    @geo.calc( p, x, y, maxDistance, distance )
  # calculate and store the geometric relationship between two things
  trig: ( t, o ) ->
    base = o.x - t.x
    height = o.y - t.y
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
  # finds the things within a particular distance of a reference thing and within a certain
  # wedge around the direction of the things movement
  # if the thing has a visual angle of 1, or the thing is motionless, all things within the distance are returned
  near: (thing, distance, angle, seen={}, candidates=@things) ->
    nearOnes = []
    tid = thing.id
    if angle == 1
      for t in candidates
        id = t.id
        continue if t.id == tid || seen[id]
        data = thing.others[id]
        continue unless data
        if @geoData[data] <= distance
          seen[id] = true
          nearOnes.push t
    else
      [ t1, t2 ] = thing.margins()
      if angle <= .5
        test = (tp) => @geo.le( t1, tp ) && @geo.ge( t2, tp )
      else
        test = (tp) => !( @geo.le( t2, tp ) && @geo.ge( t1, tp) )
      others = thing.others
      for t in candidates
        id = t.id
        continue if id == tid || seen[id]
        tp = others[id]
        continue unless tp
        if test tp
          seen[id] = true
          nearOnes.push t
    nearOnes
  # calculate part of the boundary of a dot
  topLeftArc: (radius) ->
    boundary = []
    candidatePoint = [ 0, -radius ]
    test = (pt) ->
      [ x, y ] = pt
      Math.sqrt( Math.pow( x, 2 ) + Math.pow( radius + y, 2 ) ) <= radius
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
    radius = Math.round radius
    @dotCache[radius] ||= ( =>
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
    x = Math.round x
    y = Math.round y
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
    @timer ||= @goTime
    @change  = false
    @tick   += 1
    @move()
    setTimeout(
      =>
        @recalculateGeometries()
      0
    )
  afterGeometry: ->
    self = @
    self.die()
    setTimeout(
      ->
        self.babies()
        self.done = !self.running || self.dead || !self.change
        setTimeout(
          ->
            self.draw()
            setTimeout(
              ->
                self.callback(self)
                unless self.done
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
  # anything that is starving or eaten perishes
  die: ->
    for t in shuffle @things, true
      continue if t.dead
      continue unless t.type
      switch t.type
        when Herbivore
          for other in t.touching()
            t.eat other if other instanceof Plant
        when Carnivore
          for other in t.touching()
            t.eat other if other instanceof Herbivore
      @remThing t if t instanceof Animal && t.hp <= 0
    @things = grep @things, (t) -> !t.dead
    @dead = true
    for t in @things
      if t instanceof Organism
        @dead = false
        break
  # paint a moment in time
  draw: ->
    @erase()
    t.draw() for t in @things
  # make all the current things react appropriately to the last moment in time
  move: ->
    t.react() for t in @things
  # all surviving things that are able to reproduce
  makeCradles: ->
    column = map [0...@height], -> true
    map [0...@width], -> [].concat column
  babies: ->
    cradles = @makeCradles()
    orchards = @makeCradles()
    for t in @things
      points = @pointsNear t.x, t.y, t.radius * 2
      @removeCradles cradles, points unless t instanceof Plant
      @removeCradles orchards, points unless t instanceof Stone
    for t in @things when t instanceof Organism
      c = if t instanceof Plant then orchards else cradles
      t.reproduce c
  findCradles: (allCradles, newCradles) ->
    grep newCradles, (pt) -> allCradles[pt[0]][pt[1]]
  removeCradles: (allCradles, points) ->
    for pt in points
      allCradles[pt[0]][pt[1]] = false
  # stop the universe
  stop: -> @running = false
  start: -> @run() if !@running
  # blank out the universe prior to redrawing everything
  erase: ->
    if @options.erase then @options.erase() else
      c = @canvas
      @ctx.clearRect 0, 0, c.width, c.height
  describe: ->
    map @things, (t) -> t.describe()

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
    for t in @things
      n = names[t.type] ||= t.typeName()
      counts[n] ||= 0
      counts[n] += 1
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
    @things.filter (i) -> i instanceof type
  # debugging method
  pickThing: (type) ->
    type = @getType type
    rightThings = @getThings type
    rightThings[ ~~( Math.random() * rightThings.length )]

window.Universe = Universe

# converts a vector to its angle
# solves problem introduced by angle normalization
anglify = (x, y) ->
  a = Math.abs x
  h = Math.sqrt( x*x + y*y )
  theta = Math.acos( a / h )
  if x < 0
    if y < 0 then Math.PI + theta else Math.PI - theta
  else
    if y < 0 then 2 * Math.PI - theta else theta

grep = ( ar, f ) ->
  x for x in ar when f(x)

map = ( ar, f ) ->
  f(x) for x in ar

dup = (obj) ->
  if ( obj instanceof Array )
    map obj, (o) -> dup o
  else if ( typeof obj == 'object' )
    copy = {}
    copy[k] = dup v for k, v of obj
    copy
  else
    obj

# randomization utility
shuffle = (ar, dup=false) ->
  ar = [].concat ar if dup
  i = ar.length
  while --i
    j = ~~( Math.random() * ( i + 1 ) )
    t = ar[i]
    ar[i] = ar[j]
    ar[j] = t
  ar

# something in the universe
class Thing
  constructor: ( location, options = {} ) ->
    throw "I need a universe!" unless options.universe
    @setAttributes options
    uni = @universe
    uni.change = true
    [ @x, @y ] = location
    @velocity = [ 0, 0 ]
    @radius ||= 5
    @type = Thing
    @others = {}
    uni.addThing @ unless @dontAdd
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
  draw: -> @drawBody()
  drawBody: -> @drawCircle(
      @x
      @y
      @radius
      @bodyColor || 'black'
    )
  drag: ->
  drawCircle: ( x, y, radius, color ) ->
    return unless radius > 0
    ctx = @universe.ctx
    ctx.beginPath()
    ctx.arc x, y, radius, 0, Math.PI*2
    ctx.fillStyle = color
    ctx.fill()
  setAttributes: ( options = {} ) ->
    for key, value of options
      do => @[key] = value
  # all the things whose center is within the radius of @ thing
  touching: ->
    @universe.near @, @radius, 1
  margins: ->
    m = @marges ||= []
    return m if m.length
    fi = Math.PI * @visualAngle() / 2
    t1 = @angle - fi
    t1 = @universe.tp( Math.sin(t1), Math.cos(t1) )
    t2 = @angle + fi
    t2 = @universe.tp( Math.sin(t2), Math.cos(t2) )
    m.push t1
    m.push t2
    m
  clean: ->
    for k, v in @others
      @universe.geoPool.push v if v
      delete @others[k]
    if @marges
      while @marges.length
        @universe.geoPool.push @marges.pop()
  healthRatio: -> 1

class Stone extends Thing
  constructor: ( location, options = {} ) ->
    super location, options
    @bodyColor ||= 'grey'
    @radius = options.radius || 8
    @type = Stone
  drag: -> 0

class Organism extends Thing
  constructor: ( location, options = {} ) ->
    super location, options
    @genes      ||= @defaultGenes()
    @hp         ||= @health() / 2
    @generation ||= 1
    @radius = options.radius || 5
    @tick   = @universe.tick
    @babies = 0
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
      babyTries: [ 2, 1, (t) -> Math.min( 100, t.babyTries() * 2 ) ]
      dispersalRadius: [
        => @radius * @dispersalStart()
        (t) -> t.radius * t.dispersalMin()
        (t) -> t.radius * t.dispersalMax()
      ]
      mutationRate: [ .1, 0, 1 ]
      mutationRange: [ .1, 0, 1 ]
    }
  # some things to control how far away from its mother a baby can be "born"
  dispersalStart: -> 5
  dispersalMin: -> 3
  dispersalMax: -> 20
  dispersalRadius: ->
    dr = @genes.dispersalRadius[0]
    dr = @genes.dispersalRadius[0] = dr() if typeof dr == 'function'
    dr
  # utility function for extending default genes
  mergeGenes: ( base, ext ) ->
    genes = {}
    genes[k] = v for k, v of base
    genes[k] = v for k, v of ext
    genes
  draw: ->
    super()
    @drawHunger()
  drawHunger: -> # show emptiness of belly
    h = @health()
    r = ( @radius - 1 ) * ( h - @hp ) / h
    @drawCircle( @x, @y, r, 'white' )
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
    @hp = Math.min @hp, @health()
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
      [ value, min, max ] = v
      if Math.random() <= mrate # mutation!
        mi = if typeof min == 'function' then min(@) else min
        ma = if typeof max == 'function' then max(@) else max
        delta = Math.random() * mrange * ( ma - mi )
        delta *= -1 if Math.random() > .5
        value += delta
        value = Math.max( mi, Math.min( ma, value ) )
      genes[k] = [ value, min, max ]
    genes
  # choose a pace to try to place a baby
  babyPoint: ->
    length = 2 * @radius + Math.random() * ( @dispersalRadius() - 2 * @radius )
    angle = Math.random() * Math.PI * 2
    x = Math.round( @x + length * Math.cos angle )
    y = Math.round( @y + length * Math.sin angle )
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
          if cradles[pt[0]][pt[1]]
            genes = @mitosis()
            @hp -= 1 + @babyCost()
            # put the baby in the cradle
            baby = new @type( 
              pt
              {
                universe:   @universe
                genes:      genes
                hp:         @babyCost()
                radius:     @radius
                bodyColor:  @bodyColor
                generation: @generation + 1
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
    @hr ||= @hp / @health()

class Plant extends Organism
  constructor: ( location, options = {} ) ->
    super location, options
    @bodyColor = options.bodyColor || 'green'
    @radius = options.radius || 4
    @type = Plant
  gain: -> .5
  dispersalStart: -> 15
class Animal extends Organism
  constructor: ( location, options = {} ) ->
    super location, options
    @bodyColor = options.bodyColor || 'brown'
    @radius = options.radius || 5
    # intial orientation
    @angle = Math.random() * Math.PI
    @velocity = [ 0, 0 ]
    @type = Animal
  defaultGenes: ->
    @mergeGenes super(), {
      auditoryRange: [ Math.min( @universe.maxDistance / 3, 20 ), 10, @universe.maxDistance / 2 ]
      visualAngle: [ .45, .1, 1 ]
      visualRange: [ Math.min( @universe.maxDistance / 2 , 30 ), 20, @universe.maxDistance ]
      g: [ 250, 1, 5000 ]
      jitter: [ .05, 0.01, 1 ]
      kinAffinity: [
        -2
        (t) -> -Math.max( .1, Math.abs(t.kinAffinity()) * 2 )
        (t) -> Math.max( .1, Math.abs(t.kinAffinity()) * 2 )
      ]
      foodAffinity: [
        10
        (t) -> -Math.max( .1, Math.abs(t.foodAffinity()) * 2 )
        (t) -> Math.max( .1, Math.abs(t.foodAffinity()) * 2 )
      ],
      maxAcceleration : [
        => @radius
        (t) -> t.radius / 4
        (t) -> t.maxSpeed() * 2
      ]
    }
  need: -> 0.1
  eat: (other) ->
    @hp += other.hp / 2
    @hp = Math.min( @health(), @hp ) # you can't exceed maximum health
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
  maxSpeed: -> @maxSp ||= @maxAcceleration() * 1.5
  react: ->
    super()
    x = 0
    y = 0
    g = @universe.geo
    gd = @universe.geoData
    for other in @nearby()
      influence = @affinity other
      if influence
        data = @others[other.id]
        influence /= Math.pow( gd[data], 2 )
        influence *= @g()
        [ xa, ya ] = g.vector data, influence
        x += xa
        y += ya
    if x || y
      m = Math.sqrt( x*x + y*y )
      if m > @maxAcceleration()
        f = @maxAcceleration() / m
        x *= f
        y *= f
      [ vx, vy ] = @velocity
      vx += x
      vy += y
      m = Math.sqrt( Math.pow( vx, 2 ) + Math.pow( vy, 2 ) )
      if m > @maxSpeed()
        f = @maxSpeed() / m
        vx *= f
        vy *= f
      @velocity = [ vx, vy ]
      @universe.moveThing @
  # influencing entities nearby
  auditoryRange: -> @genes.auditoryRange[0]
  nearby: ->
    candidates = @universe.near @, 1, @universe.maxDistance
    seen = {}
    nearby = @universe.near @, 1, @auditoryRange(), seen, candidates
    nearby.concat @universe.near @, @angle, @visualRange(), seen, candidates
  reactToOther: ( other, data ) ->
  prey: (other) ->
    false
  draw: ->
    super()
    @drawHead()
    @drawTail()
  # some decorations that let us see the animal's angle of vision
  # the direction of its gaze, and where it's headed
  drawHead: ->
    inc = @visualAngle() * Math.PI / 2
    la = @angle - inc
    ra = @angle + inc
    [ lx, ly ] = @edgePoint la
    [ rx, ry ] = @edgePoint ra
    @drawCircle lx, ly, 1, 'black'
    @drawCircle rx, ry, 1, 'black'
  drawTail: ->
    a = @angle + Math.PI
    [ x1, y1 ] = @edgePoint a
    [ x2, y2 ] = @edgePoint a, @radius * 1.5
    c = @universe.ctx
    c.beginPath()
    c.moveTo x1, y1
    c.lineTo x2, y2
    c.lineWidth = 2
    c.strokeStyle = @bodyColor
    c.lineCap = 'round'
    c.stroke()
  edgePoint: ( a, r = @radius ) ->
    x = @x + r * Math.cos a
    y = @y + r * Math.sin a
    [ x, y ]
  affinity: (other) ->
    switch other.type
      when @type then @kinAffinity()
      when @foodType
        @foodAffinity() * other.healthRatio() / @healthRatio()
      when Stone then -20
      else 0
class Herbivore extends Animal
  constructor: ( location, options = {} ) ->
    super location, options
    @type = Herbivore
    @foodType = Plant
  defaultGenes: ->
    @mergeGenes super(), {
      predatorAffinity: [
        -4
        (t) -> -Math.abs(Math.max(1, t.predatorAffinity())) * 2
        (t) -> Math.abs(Math.max(1, t.predatorAffinity())) * 2
      ]
    }
  affinity: (other) ->
    switch other.type
      when Carnivore then @predatorAffinity()
      else super other
class Carnivore extends Animal
  constructor: ( location, options = {} ) ->
    super location, options
    @bodyColor = options.bodyColor || 'red'
    @radius = options.radius || 6
    @type = Carnivore
    @foodType = Herbivore
  defaultGenes: ->
    @mergeGenes super(), {
      g: [ 500, 1, 5000 ]
      babyThreshold: [ .4, .1, .9 ]
      plantAffinity: [
        .1
        (t) -> -Math.abs(Math.max( 1, t.plantAffinity())) * 2
        (t) -> Math.abs(Math.max( 1, t.plantAffinity())) * 2
      ]
    }
  plantAffinity: -> @genes.plantAffinity[0]
  affinity: (other) ->
    switch other.type
      when Plant then @plantAffinity()
      else super other
