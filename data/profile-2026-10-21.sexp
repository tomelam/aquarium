(:PROJECT "aquarium" :EVENTS 54 :UNREADABLE-LINES 0 :LOGGING-ERRORS 0 :CALLS 40 :FIRST 1792604168 :LAST 1792604323
 :CELLS (((:NONE :CAUGHT) 26) ((:NONE :MISSED) 13) ((:NONE :PENDING) 1)) :GUARD-ONLY-CATCHES COMMON-LISP:NIL
 :DENY-ONLY-CATCHES
 (("cat /dev/null" . 1) ("head -n 1 /dev/null" . 1) ("wc -l /dev/null" . 1) ("grep x /dev/null" . 1)
  ("sed -n 1p /dev/null" . 1) ("python3 -c pass" . 1) ("ls /dev/null | wc -l" . 1)
  ("ls /dev/null && cat /dev/null" . 1) ("FOO=1 grep x /dev/null" . 1) ("echo $(cat /dev/null)" . 1)
  ("echo \"$(cat /dev/null)\"" . 1) ("(cat /dev/null)" . 1) ("timeout 5 grep x /dev/null" . 1)
  ("nice -n 5 grep x /dev/null" . 1) ("timeout -k 5 10 grep x /dev/null" . 1) ("xargs grep x < /dev/null" . 1)
  ("echo /dev/null | xargs cat" . 1) ("env FOO=1 sed -n 1p /dev/null" . 1) ("sudo -n cat /dev/null" . 1)
  ("'cat' /dev/null" . 1) ("for f in /dev/null; do cat $f; done" . 1) ("if true; then cat /dev/null; fi" . 1)
  ("{ cat /dev/null; }" . 1) ("! grep x /dev/null" . 1) ("cat</dev/null" . 1))
 :BOTH-CAUGHT COMMON-LISP:NIL :CANDIDATES-BOTH-MISSED
 (("echo /dev/null | xargs -I {} cat {}" . 1) ("echo /dev/null | xargs -n1 grep x" . 1)
  ("eval 'sed -n 1p /dev/null'" . 1) ("/usr/bin/sed -n 1p /dev/null" . 1) ("/bin/cat /dev/null" . 1)
  ("sh -c 'cat /dev/null'" . 1) ("bash -c 'cat /dev/null'" . 1) ("find /dev/null -exec cat {} +" . 1) ("echo sed" . 1))
 :CORPUS-NOT-YET-RUN COMMON-LISP:NIL)
