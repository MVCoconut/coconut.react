package coconut.react;

import coconut.ui.macros.ViewBuilder;

class View {
  static function hxx(_, e)
    return coconut.react.macros.HXX.parse(e);

  static var reserved(get, null):Map<String, Bool>;
    static function get_reserved()
      return switch reserved {
        case null:
          reserved = [for (f in Context.getType('react.ReactComponent').getClass().fields.get())
            f.name => true
          ];
        case v: v;
      }

  static function afterBuild(ctx:ViewInfo) {

    var cls = ctx.target.target;

    for (m in ctx.target)
      if (reserved[m.name])
        m.addMeta(':native', (macro null).pos, [macro $v{'__coco_' + m.name}]);

    var self = toComplex(cls);

    var hxxMeta = {
      var refType =
        if (Context.defined('display')) macro : Dynamic // things typed in display shouldn't be cached, so let's hope this is an ok way to sidestep issues.
        else macro : coconut.ui.Ref<$self>;

      macro : {
        @:optional var key(default, never):coconut.react.Key;
        @:optional var ref(default, never):$refType;
      }
    }

    var attributeFields = ctx.attributes.copy();
    var attributes = TAnonymous(attributeFields);

    {
      var ctor = ctx.target.getConstructor();
      @:privateAccess switch ctor.meta { //TODO: this is rather horrible
        case null:
          ctor.meta = [{ name: ':keep', params: [], pos: ctor.pos }];
        case meta:
          meta.push({ name: ':keep', params: [], pos: ctor.pos });
      }
    }

    var states = [];
    var stateMap = EObjectDecl(states).at();

    for (s in ctx.states) {
      var s = s.name;
      states.push({
        field: s,
        expr: macro function () return this.$s,
      });
    }

    #if react_devtools
    ctx.target.getConstructor().addStatement(macro this.__stateMap = $stateMap);
    #end


    var reactType = macro cast $i{ctx.target.target.name};

    // HOC wrap
    switch cls.meta.extract(':react.hoc') {
      case []:
        // do nothing
      case wraps:
        var wrapped = macro cast $i{ctx.target.target.name};

        for(i in 0...wraps.length) { // loop in reverse, so that the first meta will become the outermost wrap
          switch wraps[wraps.length - i - 1] {
            case {params: [wrapper]}:
              wrapped = macro $wrapper($wrapped);
            case {params: [wrapper, e = macro (_:$ct)]}: // https://github.com/HaxeFoundation/haxe-evolution/pull/44
              switch ct.toType() {
                case Success(_.reduce().toComplex() => TAnonymous(fields)):
                  for(field in fields) {
                    switch field.kind {
                      case FVar(ct, e): field.kind = FVar(macro:coconut.data.Value<$ct>, e);
                      case FProp(get, set, ct, e): field.kind = FProp(get, set, macro:coconut.data.Value<$ct>, e);
                      case _: // TODO:
                    }
                    attributeFields.push(field);
                  }
                case _:
                  e.pos.error('Expected anonymous structure type');
              }
              wrapped = macro $wrapper($wrapped);
            case {params: [wrapper, _], pos: pos}:
              pos.error('Second parameter of @:wrap should be a ETypeCheck expr');
            case {pos: pos}:
              pos.error('@:wrap must have one or two parameters');
          }
        }

        ctx.target.addMembers(macro class {
          @:keep static var __hoc:react.ReactType = $wrapped;
        });

        reactType = macro $reactType.__hoc;
    }

    // injected props
    var init =
      switch ctx.target.memberByName('__initAttributes') {
        case Success({kind: FFun(f)}): f;
        case _: throw 'unreachable';
      }

    for(member in ctx.target)
      switch [member.kind, member.meta.filter(function(meta) return meta.name == ':react.injected')] {
        case [_, []]:
          // skip
        case [FFun(_), _]:
          member.pos.error('@:react.injected does not work on functions');
        case [FVar(ct, e) | FProp(_, _, ct, e), [meta = {params: params}]]:
          if(e != null) e.pos.error('Field with @:react.injected cannot have an initializer');
          var name = switch params {
            case []:
              member.name;
            case [macro $v{(name:String)}]:
              name;
            case _:
              meta.pos.error('@:react.injected should have at most one parameter');
          }
          var internal = '__coco_${member.name}';
          var getter = 'get_${member.name}';

          member.kind = FProp('get', 'never', ct, null);
          ctx.target.addMembers(macro class {
            @:noCompletion private var $internal:coconut.ui.internal.Slot<$ct, coconut.data.Value<$ct>>;
            inline function $getter() return $i{internal}.value;
          });

          ctx.target.getConstructor().addStatement(macro this.$internal = new coconut.ui.internal.Slot(this), true);

          init.expr = init.expr.concat(macro {
            var value:$ct = (cast $i{init.args[0].name}).$name;
            $i{internal}.setData(tink.state.Observable.const(value));
          });

        case _:
          member.pos.error('Multiple @:react.injected is not supported');
      }

    var magic = "$$typeof";
    var added = ctx.target.addMembers(macro class {
      #if react_devtools
      @:keep @:noCompletion var __stateMap:{};
      #end
      static public function fromHxx(hxxMeta:$hxxMeta, attributes:$attributes):coconut.ui.RenderResult
        return {
          $magic: coconut.react.View.TRE,
          type: $reactType,
          props: attributes,
          key: hxxMeta.key,
          ref: if (!cast hxxMeta.ref) null else hxxMeta.ref,
        }
    });

    var fromHxx = added[added.length - 1];
    fromHxx.pos = cls.pos;
    parametrize(fromHxx, cls);

  }
  static function autoBuild()
    return ViewBuilder.autoBuild({
      renders: macro : coconut.react.RenderResult,
      implicits: {
        name: '__react_context',
        fields: (macro class {
          @:keep static final contextType = @:privateAccess coconut.react.Implicit.contextType;
        }).fields,
      },
      afterBuild: afterBuild,
    });
}