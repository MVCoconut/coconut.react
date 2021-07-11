package coconut.react;

abstract Key(Dynamic) from String from Bool from Float from Int #if genes from {} #end {
  #if !genes
  @:keep @:from static function ofObj(o:{}):Key untyped {
    var id = haxe.ds.ObjectMap.getId(o) || haxe.ds.ObjectMap.assignId(o);
    return id;
  }
  #end
}