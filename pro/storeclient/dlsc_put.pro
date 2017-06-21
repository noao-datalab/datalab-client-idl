;+
;
; DLSC_PUT
;
; Upload a file to the store manager service.
;
; INPUTS:
;  token      Secure token obtained via dlac_login.
;  fr         The name of the local source file to put to VOSpace.
;  to         The name of the destination file in VOSpace.
;  /verbose   Verbose output.
;
; OUTPUTS:
;  Result     'OK' if everything succeeded.
;
; USAGE:
;  IDL>res = dlsc_put(token,'file.txt','file2.txt')
;
; By D. Nidever   June 2017, translated from storeClient.py
;-
 
function dlsc_put,token,fr,to,verbose=verbose

compile_opt idl2
On_error,2

; Initialize the DL Storage global structure
DEFSYSV,'!dls',exists=dlsexists
if dlsexists eq 0 then DLSC_CREATEGLOBAL

; Not enough inputs
if n_elements(token) eq 0 then message,'Token not input'
if n_elements(fr) eq 0 then message,'fr not input'
if n_elements(to) eq 0 then message,'to not input'
; Defaults
if n_elements(verbose) eq 0 then verbose=1
debug = 0
headers = 'X-DL-AuthToken: '+token

; Patch the names with the URI prefix if needed.
;if strmid(to,0,6) eq 'vos://' then nm=fr else nm='vos://'+fr


; If the 'to' is a directory, create it first and then transfer the
; contents.
if file_test(fr,/directory) then begin
  if strmid(fr,0,1,/reverse_offset) eq '/' then begin
    if strmid(to,0,6) eq 'vos://' then dname=to else dname=strmid(to,0,len(to)-1)
    r = dlsc_mkdir(token, dname)
  endif
  flist = file_search(fr+'/*')
endif else begin
  dname = ''
  flist = fr 
endelse

if keyword_set(debug) then begin
  print,'fr='+fr+'  to='+to+'  dname='+dname
  print,strtrim(flist,2) 
endif

nfiles = n_elements(flist)
fnum = 1
for i=0,nfiles-1 do begin
  f = flist[i]
  fr_dir = file_dirname(f)
  fr_name = file_basename(f)

  ; Patch the names with the URI prefix if needed.
  if strmid(to,0,6) eq 'vos://' then nm=to else nm='vos://'+to
  if strmid(to,0,1,/reverse_offset) eq '/' then nm=nm+fr_name

  if keyword_set(debug) then print,'put: f='+f+' nm='+nm

  if not file_test(f) then begin
    ; Skip files that don't exist
    print,'Error: file '+f+' does not exist'
    continue 
  endif

  url1 = !dls.svc_url + "/put?name="+nm
  r = ""
  ourl = obj_new('IDLnetURL')
  ourl->SetProperty,headers=headers
  url2 = ourl->get(/string_array,url=url1)
  ourl->GetProperty,response_code=status_code
  obj_destroy,ourl            ; destroy when we are done
  
  ; Cannot upload directly to a container
  ; if r.status_code == 500 and r.content == "Data cannot be uploaded to a
  ; container":
  if status_code eq 500 then begin
    file = file_basename(fr)
    nm += '/'+f 
     
    url1 = !dls.svc_url + "/put?name="+nm
    response = ""
    ourl = obj_new('IDLnetURL')
    ourl->SetProperty,headers=headers
    url2 = ourl->get(/string_array,url=url1)
    ourl->GetProperty,response_code=status_code
    obj_destroy,ourl            ; destroy when we are done
  endif
    
  if keyword_set(verbose) then $
     print,'('+strtrim(fnum,2)+' / '+strtrim(nfiles,2)+' ) '+f+' -> ',format='(A,$)'
     ; add $ to format string to suppres newline
  
  ; Use SOCKET for PUT call
  urlstr = urlparse(url2)
  server = urlstr.host
  port = urlstr.port
  UserAgentString= "IDL "+!version.release+' on '+!VERSION.OS+'/'+!VERSION.ARCH
  finfo = file_info(f)
  socket, unit, urlstr.host,  long(urlstr.port), /get_lun,/swap_if_little_endian, $
          connect_timeout=timeout,read_timeout=timeout
  printf,unit,'PUT /'+urlstr.path+' HTTP/1.1'
  printf,unit,'Host: dldb1.sdm.noao.edu'
  printf,unit,'User-Agent: '+ UserAgentString
  printf,unit,'Connection: close'
  ;printf,unit,'Keep-Alive: 300'
  ;printf,unit,'Connection: keep-alive'
  printf,unit,'Content-Type: application/octet-stream'
  printf,unit,'Content-Length: '+strtrim(finfo.size,2)
  printf,unit,'X-DL-AuthToken: '+token
  printf,unit,''    ; need blank line b/w header and content
  ; Load the data and write to socket
  openr, runit, f, /get_lun
  aaa = bytarr(finfo.size,/nozero)
  readu, runit, aaa
  writeu, unit, aaa
  free_lun, runit
  ; Now read the response header
  line = ' '
  undefine,response_header
  while(line ne '') do begin
    readf,unit,line
    push,response_header,line
  endwhile
  free_lun, unit
  close,unit

  ; IDLnetURL PUT is currently causing segmentation faults
  ;  Using SOCKET for now.
  ;response = ""
  ;ourl = obj_new('IDLnetURL')
  ;ourl->SetProperty,headers='Content-type: application/octet-stream'
  ;ourl->SetProperty,headers=headers
  ;response = ourl->put(f,url=url2)
  ;ourl->GetProperty,response_code=status_code
  ;obj_destroy,ourl            ; destroy when we are done

  if keyword_set(verbose) then print,nm
                
  fnum += 1
endfor

return,''

end
