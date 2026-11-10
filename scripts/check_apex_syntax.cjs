const fs = require('node:fs'); const path = require('node:path');
const { ApexParserFactory, ApexErrorListener } = require('@apexdevtools/apex-parser');
const root=path.resolve(__dirname,'..');let count=0;const errors=[];
class Listener extends ApexErrorListener { constructor(file){super();this.file=file;} apexSyntaxError(line,column,message){errors.push({file:this.file,line,column,message});} }
for(const folder of ['classes','triggers']) for(const file of fs.readdirSync(path.join(root,'force-app/main/default',folder)).sort()) {
 if(!/\.(cls|trigger)$/.test(file))continue;
 const relative='force-app/main/default/'+folder+'/'+file;
 const {parser}=ApexParserFactory.createLexerAndParser(fs.readFileSync(path.join(root,relative),'utf8'),new Listener(relative));
 if(file.endsWith('.trigger')) parser.triggerUnit();else parser.compilationUnit();count++;
}
process.stdout.write(JSON.stringify({filesParsed:count,errors},null,2)+'\n');process.exitCode=errors.length?1:0;
