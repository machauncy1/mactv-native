(()=>{
  if(!/(^|\.)(youtube\.com|netflix\.com|bilibili\.com)$/.test(location.hostname))return;
  function apply(){
    for(const video of document.querySelectorAll('video'))for(const track of video.textTracks||[])track.mode='disabled';
    if(!document.getElementById('mactv-no-captions')){
      const style=document.createElement('style');style.id='mactv-no-captions';
      style.textContent='.ytp-caption-window-container,.caption-window,.captions-text,.ytp-subtitles-button,.player-timedtext,.player-timedtext-text-container,.bpx-player-subtitle,.bpx-player-subtitle-wrap,.bpx-player-subtitle-panel,[data-mactv-theatre] [class*="subtitle"],[data-mactv-theatre] [class*="caption"]{display:none!important}';
      document.head.appendChild(style);
    }
  }
  apply();setInterval(apply,1000);
})();
