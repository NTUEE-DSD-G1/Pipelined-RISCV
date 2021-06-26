Folder structure:
rtl/: rtl codes for submission(to run tb)
syn/: synthesis files for submission(to run tb)
others/: other spec we used/wrote to help us go deeper in L2 Cache
  baseline/: same as baseline design, just to compare with other spec
  DCache/: only implement L2 D-Cache
  split/: implement split I/D Cache
  unified/: unified L2 Cache
  (for more specific info, please refer to readme.txt in each folder)

* In rtl/ & syn/, we use DCache's files (which only implement L2 D-Cache),
* Since L2 I-Cache won't do any better on provided tb.