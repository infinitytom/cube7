#!/bin/bash
# 把各段录像剪成一条演示视频
set -e
cd /tmp/demo
FONT=/home/claude/Cube7/assets/fonts/ZCOOLKuaiLe.ttf
mkdir -p seg
clip() { # name start end caption
  local n=$1 s=$2 e=$3 cap="$4"
  local d=$(python3 -c "print(round($e-$s,3))")
  local fo=$(python3 -c "print(round($e-$s-0.35,3))")
  local vf="trim=start=$s:end=$e,setpts=PTS-STARTPTS,fps=30,scale=1280:720,format=yuv420p,fade=t=in:st=0:d=0.3,fade=t=out:st=$fo:d=0.35"
  if [ -n "$cap" ]; then
    vf="$vf,drawtext=fontfile=$FONT:text='$cap':fontsize=46:fontcolor=white:borderw=4:bordercolor=0x1a2340:x=60:y=h-150:alpha='if(lt(t,0.4),t/0.4,if(gt(t,$d-0.5),($d-t)/0.5,1))'"
  fi
  ffmpeg -v error -y -i $n.avi -vf "$vf" -af "atrim=start=$s:end=$e,asetpts=PTS-STARTPTS,aresample=48000,afade=t=in:st=0:d=0.3,afade=t=out:st=$fo:d=0.35" \
    -c:v libx264 -preset medium -crf 20 -c:a aac -b:a 160k -ar 48000 -ac 2 seg/$n.mp4
}
clip title 0.2 10.8 ""
clip gh 1.3 15.6 "撞碎 · 下砸 · 重构波把坑填回去"
clip ghsite 2.4 9.2 "攒够重构物质，瞭望台一块块建起来"
clip gw 1.4 6.6 "蓄力冲撞，连盾牌一起撞碎"
clip city 1.2 9.5 "第四章 · 天空城市"
clip rust 1.2 12.0 "第五章 · 灯塔从锈海里重建"
clip core 1.2 11.2 "终章 · 锈蚀之心"
clip editor 0.8 7.0 "关卡编辑器：自己搭关卡，一键试玩"
# 片尾
ffmpeg -v error -y -f lavfi -i color=c=0x0b1024:s=1280x720:d=3:r=30 -f lavfi -i anullsrc=r=48000:cl=stereo -t 3 \
  -vf "drawtext=fontfile=$FONT:text='方舟星球 Voxel Ark':fontsize=84:fontcolor=white:x=(w-tw)/2:y=h/2-90,drawtext=fontfile=$FONT:text='github.com/infinitytom/cube7':fontsize=36:fontcolor=0x7fd8ff:x=(w-tw)/2:y=h/2+30,fade=t=in:st=0:d=0.5,format=yuv420p" \
  -c:v libx264 -crf 20 -c:a aac -b:a 160k -ar 48000 -ac 2 -shortest seg/end.mp4
ls seg/*.mp4
printf "file 'seg/%s.mp4'\n" title gh ghsite gw city rust core editor end > list.txt
ffmpeg -v error -y -f concat -safe 0 -i list.txt -c copy demo.mp4
ffprobe -v error -show_entries format=duration -of csv=p=0 demo.mp4
