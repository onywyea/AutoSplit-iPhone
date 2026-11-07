"""Ten distinct vector silhouettes; Apple Icon Composer supplies the glass optics."""
from pathlib import Path
import json
root = Path(__file__).resolve().parents[1] / 'AutoSplit'
def path(d, width=0):
    return f'<path d="{d}" fill="none" stroke="white" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round"/>' if width else f'<path d="{d}" fill="white"/>'
def rect(x,y,w,h,r=30): return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="white"/>'
def circle(x,y,r,width=0): return f'<circle cx="{x}" cy="{y}" r="{r}" fill="none" stroke="white" stroke-width="{width}"/>' if width else f'<circle cx="{x}" cy="{y}" r="{r}" fill="white"/>'
def svg(body): return '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'+body+'</svg>'
collection = [
 ('Prism','prism','Призма',('0.440,0.310,0.760','0.080,0.045,0.210'),[
 path('M512 176 788 334 788 674 512 848 236 674 236 334Z'),
 path('M512 176 512 512 788 334Z M236 674 512 512 512 848Z'),
 path('M402 358H544L622 436V650Q622 674 598 674H426Q402 674 402 650Z')]),
 ('Stack','stack','Шари',('0.150,0.540,0.800','0.020,0.100,0.260'),[
 '<g transform="rotate(-13 512 512)">'+rect(254,220,390,560,52)+'</g>',
 '<g transform="rotate(10 512 512)">'+rect(364,238,390,560,52)+'</g>',
 rect(310,246,404,566,52),path('M394 408H626M394 490H626M394 572H548',24)]),
 ('Lens','lens','Об’єктив',('0.310,0.360,0.420','0.025,0.035,0.060'),[
 circle(512,512,300,42),
 ''.join('<g transform="rotate('+str(a)+' 512 512)">'+path('M512 242Q672 258 710 392L564 474 446 388Z')+'</g>' for a in range(0,360,120)),
 rect(422,422,180,180,48)]),
 ('Ribbon','ribbon','Потік S',('0.720,0.400,0.300','0.220,0.065,0.120'),[
 path('M714 310H422C272 310 272 492 422 492H586C746 492 746 706 586 706H300',100),
 path('M674 278H422C342 278 300 336 300 394',22),
 path('M350 738H586C668 738 718 676 718 610',22)]),
 ('Portal','portal','Портал',('0.120,0.520,0.540','0.015,0.110,0.170'),[
 path('M260 778V424C260 90 764 90 764 424V778H672V424C672 210 352 210 352 424V778Z'),
 rect(402,390,220,338,36),
 rect(196,674,632,44,22)+path('M452 476H572M452 536H572',18)]),
 ('Folio','folio','Фоліо',('0.640,0.560,0.380','0.180,0.120,0.055'),[
 path('M194 286Q346 224 492 316V784Q346 692 194 752Z'),
 path('M532 316Q678 224 830 286V752Q678 692 532 784Z'),
 path('M266 378Q358 350 420 394M266 456Q358 428 420 472M604 394Q676 350 758 378M604 472Q676 428 758 456',23)]),
 ('Orbit','orbit','Орбіта',('0.230,0.410,0.850','0.045,0.075,0.240'),[
 '<ellipse cx="512" cy="512" rx="354" ry="210" transform="rotate(-32 512 512)" fill="none" stroke="white" stroke-width="36"/>',
 rect(370,266,284,490,42),
 circle(786,340,58)+circle(232,680,38)+path('M434 414H590M434 482H590M434 550H544',23)]),
 ('Wave','wave','Хвиля',('0.180,0.630,0.590','0.020,0.150,0.170'),[
 path('M260 270Q390 206 512 270T764 270V750Q640 814 512 750T260 750Z'),
 path('M260 438Q390 374 512 438T764 438V552Q640 616 512 552T260 552Z'),
 path('M344 334Q426 308 488 340M344 646Q426 620 488 652',24)]),
 ('Archive','archive','Архів',('0.500,0.330,0.570','0.140,0.045,0.180'),[
 rect(222,356,580,430,64),
 rect(324,206,376,348,40)+rect(198,414,628,94,35),
 rect(414,594,196,46,23)+path('M398 302H626',22)]),
 ('Facet','facet','Кристал',('0.550,0.670,0.310','0.110,0.180,0.065'),[
 path('M316 226H708L858 462 512 836 166 462Z'),
 path('M316 226 398 462 166 462Z M708 226 626 462 858 462Z M398 462 512 836 626 462Z'),
 path('M398 462 512 288 626 462 512 590Z')])]
catalog=[]
for suffix,case,title,colors,layers in collection:
 name='ScanFlow'+suffix;p=root/(name+'.icon');(p/'Assets').mkdir(parents=True,exist_ok=True)
 groups=[]
 for i,body in enumerate(layers):
  filename=f'Layer{i+1}.svg';(p/'Assets'/filename).write_text(svg(body))
  groups.append({'name':f'Optical layer {i+1}','layers':[{'name':f'Shape {i+1}','image-name':filename,'glass':True}], 'specular':True,'shadow':{'kind':'neutral','opacity':0.15},'translucency':{'enabled':True,'value':0.3 if i==0 else 0.2}})
 manifest={'fill':{'linear-gradient':['srgb:'+c+',1.000' for c in colors]},'groups':groups,'supported-platforms':{'squares':'shared'}}
 (p/'icon.json').write_text(json.dumps(manifest,indent=2)+'\n')
 catalog.append({'case':case,'name':name,'title':title})
(root/'IconCollection.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')
print('Generated',len(catalog),'distinct native glass icon packages')
