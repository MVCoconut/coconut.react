package coconut.react.macros;

#if macro
import tink.hxx.*;

class HXX {
  static public var generator = new Generator();

  static public function parse(e)
    return coconut.ui.macros.Helpers.parse(e, generator, 'coconut.react.View.createFragment');
}
#end