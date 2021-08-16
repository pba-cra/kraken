import ts, {HeritageClause, ScriptTarget} from 'typescript';
import {Blob} from './blob';
import {
  ClassObject,
  FunctionArguments,
  FunctionDeclaration,
  PropsDeclaration,
  PropsDeclarationKind
} from './declaration';
import {generatorSource} from './generator';

export function analyzer(blob: Blob) {
  let code = blob.raw;
  const sourceFile = ts.createSourceFile(blob.source, blob.raw, ScriptTarget.ES2020);
  blob.objects = sourceFile.statements.map(statement => walkProgram(statement)).filter(o => o instanceof ClassObject) as ClassObject[];
  generatorSource(blob);
}

function getInterfaceName(statement: ts.Statement) {
  return (statement as ts.InterfaceDeclaration).name.escapedText;
}

function getHeritageType(heritage: HeritageClause) {
  let expression = heritage.types[0].expression;
  if (expression.kind === ts.SyntaxKind.Identifier) {
    return (expression as ts.Identifier).escapedText;
  }
  return null;
}

function getPropKind(type: ts.TypeNode): PropsDeclarationKind {
  if (type.kind === ts.SyntaxKind.StringKeyword) {
    return PropsDeclarationKind.string;
  } else if (type.kind === ts.SyntaxKind.NumberKeyword) {
    return PropsDeclarationKind.number;
  } else if (type.kind === ts.SyntaxKind.BooleanKeyword) {
    return PropsDeclarationKind.boolean;
  } else if (type.kind === ts.SyntaxKind.FunctionType) {
    return PropsDeclarationKind.function;
  }
  return PropsDeclarationKind.object;
}

function getPropName(propName: ts.PropertyName) {
  if (propName.kind == ts.SyntaxKind.Identifier) {
    return propName.escapedText.toString();
  } else if (propName.kind === ts.SyntaxKind.StringLiteral) {
    return propName.text;
  } else if (propName.kind === ts.SyntaxKind.NumericLiteral) {
    return propName.text;
  }
  throw new Error(`prop name: ${ts.SyntaxKind[propName.kind]} is not supported`);
}

function getParameterName(name: ts.BindingName) : string {
  if (name.kind === ts.SyntaxKind.Identifier) {
    return name.escapedText.toString();
  }
  return  '';
}

function getParameterType(type: ts.TypeNode) : string {
  if (type.kind === ts.SyntaxKind.StringKeyword) {
    return 'string';
  } else if (type.kind === ts.SyntaxKind.NumberKeyword) {
    return 'number';
  } else if (type.kind === ts.SyntaxKind.BooleanKeyword) {
    return 'boolean';
  }
  return 'UnionType';
}

function paramsNodeToArguments(parameter: ts.ParameterDeclaration): FunctionArguments {
  let args = new FunctionArguments();
  args.name = getParameterName(parameter.name);
  args.type = getParameterType(parameter.type!);
  args.required = !parameter.questionToken;
  return args;
}

function walkProgram(statement: ts.Statement) {
  switch(statement.kind) {
    case ts.SyntaxKind.InterfaceDeclaration: {
      let interfaceName = getInterfaceName(statement);
      if (interfaceName === 'HostObject' || interfaceName === 'HostClass') return;
      let s = (statement as ts.InterfaceDeclaration);
      let obj = new ClassObject();
      if (s.heritageClauses) {
        let heritage = s.heritageClauses[0];
        let heritageType = getHeritageType(heritage);
        if (heritageType) obj.type = heritageType.toString();
      }

      obj.name = s.name.escapedText.toString();

      s.members.forEach(member => {
        switch(member.kind) {
          case ts.SyntaxKind.PropertySignature: {
            let prop = new PropsDeclaration();
            let m = (member as ts.PropertySignature);
            prop.name = getPropName(m.name);

            let propKind = m.type;
            if (propKind) {
              prop.kind = getPropKind(propKind);
              if (prop.kind === PropsDeclarationKind.function) {
                let f = (m.type as ts.FunctionTypeNode);
                let functionProps = prop as FunctionDeclaration;
                functionProps.args = [];
                f.parameters.forEach(params => {
                  let p = paramsNodeToArguments(params);
                  functionProps.args.push(p);
                });
                obj.methods.push(functionProps);
              } else {
                obj.props.push(prop);
              }
            }

            break;
          }
          case ts.SyntaxKind.MethodSignature: {
            let m = (member as ts.MethodSignature);
            let f = new FunctionDeclaration();
            f.name = getPropName(m.name);
            f.kind = PropsDeclarationKind.function;
            f.args = [];
            m.parameters.forEach(params => {
              let p = paramsNodeToArguments(params);
              f.args.push(p);
            });
            obj.methods.push(f);
          }
        }
      });

      return obj;
    }
  }

  return null;
}
