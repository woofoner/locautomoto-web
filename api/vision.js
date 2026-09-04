export default async function handler(req,res){
  res.setHeader('Access-Control-Allow-Origin','*');
  res.setHeader('Access-Control-Allow-Headers','Content-Type');
  res.setHeader('Access-Control-Allow-Methods','POST,OPTIONS');
  if(req.method==='OPTIONS')return res.status(204).end();
  if(req.method!=='POST')return res.status(405).json({error:'Method not allowed'});
  const key=process.env.OPENAI_API_KEY;
  if(!key)return res.status(503).json({error:'Vision backend not configured'});
  const image=req.body?.image;
  const side=String(req.body?.side||'document');
  const docType=String(req.body?.docType||'id');
  if(typeof image!=='string'||!image.startsWith('data:image/')){
    return res.status(400).json({error:'Invalid image'});
  }
  if(image.length>12_000_000)return res.status(413).json({error:'Image too large'});

  const prompt = [
    "Analyze this identity document image visually, not only by OCR.",
    "Return ONLY one valid JSON object, no markdown.",
    "Extract only fields you can actually see. Never invent missing values.",
    "Fields: surname, first, birthDate, sex, nationality, documentNumber, expiryDate, issueDate, address, country, countryCode, type.",
    "Use birthDate/expiryDate/issueDate as YYYY-MM-DD when confidently inferable, otherwise empty string.",
    "Use sex as homme, femme, autre, or empty string.",
    "Preserve accents and spelling from the document.",
    "Document side: "+side+". Expected kind: "+docType+"."
  ].join("\n");

  try{
    const r=await fetch('https://api.openai.com/v1/responses',{
      method:'POST',
      headers:{
        'Authorization':'Bearer '+key,
        'Content-Type':'application/json'
      },
      body:JSON.stringify({
        model:'gpt-5.6-luna',
        input:[{
          role:'user',
          content:[
            {type:'input_text',text:prompt},
            {type:'input_image',image_url:image}
          ]
        }]
      })
    });
    const j=await r.json();
    if(!r.ok)return res.status(r.status).json({error:j?.error?.message||'Vision API error'});
    const texts=[];
    if(Array.isArray(j.output)){
      for(const item of j.output){
        if(Array.isArray(item?.content)){
          for(const c of item.content){
            if(typeof c?.text==='string')texts.push(c.text);
          }
        }
      }
    }
    let text=texts.join('\n').trim();
    text=text.replace(/^\`\`\`(?:json)?/i,'').replace(/\`\`\`$/,'').trim();
    const start=text.indexOf('{'), end=text.lastIndexOf('}');
    if(start<0||end<start)throw new Error('Invalid model JSON');
    const data=JSON.parse(text.slice(start,end+1));
    return res.status(200).json(data);
  }catch(e){
    console.error(e);
    return res.status(500).json({error:'Vision analysis failed'});
  }
}
