(()=>{
 if(location.hostname!=='space.bilibili.com'||window.MacTVCreator)return;
 const text=e=>(e?.textContent||'').replace(/\s+/g,' ').trim();
 const visible=e=>{const r=e.getBoundingClientRect();return r.width>0&&r.height>0;};
 function read(){
  const videos=[],seen=new Set();
  for(const link of document.querySelectorAll('a[href*="/video/BV"]')){
   let u;try{u=new URL(link.href,location.href);}catch{continue;}
   if(!['www.bilibili.com','bilibili.com'].includes(u.hostname)||!/^\/video\/BV[A-Za-z0-9]+\/?$/.test(u.pathname))continue;
   const key='https://www.bilibili.com'+u.pathname.replace(/\/?$/,'/');if(seen.has(key))continue;
   const root=link.closest('.bili-video-card,.small-item,.upload-video-card,.video-card,.bili-video-card__wrap,.bili-video-card__info')||link.parentElement;
   const image=root?.querySelector('img');if(!image)continue;
   let poster;for(const value of [image.getAttribute('src'),image.getAttribute('data-src'),image.currentSrc,image.src]){try{const candidate=new URL(value||'',location.href);if(candidate.protocol==='https:'&&/(^|\.)(hdslb\.com|biliimg\.com|bilibili\.com)$/.test(candidate.hostname)){poster=candidate;break;}}catch{}}if(!poster)continue;
   const label=root.querySelector('.bili-video-card__info--tit,.bili-video-card__title,.title,h3,[title]');
   const title=label?.getAttribute('title')||text(label)||link.getAttribute('title')||image.alt||text(link);if(!title||title.length>180)continue;
   const duration=text(root.querySelector('.bili-video-card__stats__duration,.bili-video-card__duration,.length,.duration,[class*="duration"],.bili-cover-card__stat:last-child span'));
   seen.add(key);videos.push({id:key,title,poster:poster.href,duration});
  }
  const collections=[];
  for(const header of document.querySelectorAll('.video-list__header')){
   const name=header.querySelector('.video-list__title,[class*="title"]');
   const label=text(name)||text(header).replace(/播放全部|查看更多/g,'').trim();
   const block=header.parentElement,img=block?.querySelector('img');if(!label)continue;
   const duration=text(header.querySelector('.video-list__desc')).match(/(?:^|·)\s*(\d+)\s*$/)?.[1]??label.match(/·\s*(\d+)\s*$/)?.[1];
   let poster='';try{poster=img?new URL(img.currentSrc||img.src,location.href).href:'';}catch{}
   collections.push({id:label,title:label.replace(/^(合集|系列)[·\s]*/,'').replace(/·\s*\d+\s*$/,'').trim(),poster,count:duration==null?null:Number(duration),detail:duration?duration+' 个视频':''});
  }
  const body=text(document.body);
  const next=[...document.querySelectorAll('button')].find(e=>text(e)==='下一页');
  const finished=(!!next&&(next.disabled||/disabled/.test(next.className)))||(collections.length>0&&!next);
  const empty=/\/lists\/\d+/.test(location.pathname||'')&&videos.length===0&&/0\s*个视频/.test(body)&&/这里还什么都没有|暂无视频|没有更多视频/.test(body);
  return {collections,videos,empty,blocked:videos.length===0&&/安全验证|访问过于频繁|请先登录后查看/.test(body),finished:empty||finished||/没有更多了|暂无更多|没有更多视频|还没有创建|暂无合集|暂无系列|暂无数据/.test(body)};
 }
 function more(){
  window.scrollTo(0,document.documentElement.scrollHeight);
  const next=[...document.querySelectorAll('button,.be-pager-next,.vui_pagination--btn-side')].find(e=>/^(下一页|下页|Next)$/.test(text(e))&&!e.disabled&&!/disabled/.test(e.className)&&visible(e));
  if(next){next.click();return true;}return true;
 }
 function openCollection(title){
  for(const header of document.querySelectorAll('.video-list__header')){
   const name=header.querySelector('.video-list__title,[class*="title"]');
   const label=text(name)||text(header).replace(/播放全部|查看更多/g,'').trim();
   if(label!==title)continue;
   const button=[...header.querySelectorAll('button')].find(e=>text(e)==='查看更多');if(button){button.click();return true;}
  }return false;
 }
 window.MacTVCreator={read,more,openCollection};
})();
