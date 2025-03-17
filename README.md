# pipeline-from-goa
The new GO pipeline that runs after GOA has made QC file products available.

## SOP for new run

Something like:

```
cd ~/confinement-for-pipeline-388/
rm *.gaf union* panther_proteomes.gaf.tar.gz
wget https://ftp.ebi.ac.uk/pub/contrib/goa/panther_proteomes/panther_proteomes.gaf.tar.gz
tar -zxvf panther_proteomes.gaf.tar.gz
cat A*.gaf B*.gaf C*.gaf D*.gaf E*.gaf F*.gaf G*.gaf > union1.gaf
cat H*.gaf I*.gaf J*.gaf K*.gaf L*.gaf M*.gaf N*.gaf > union2.gaf
cat O*.gaf P*.gaf R*.gaf S*.gaf T*.gaf U*.gaf > union3.gaf
cat V*.gaf W*.gaf X*.gaf Y*.gaf Z*.gaf > union4.gaf
gzip union1.gaf && gzip union2.gaf && gzip union3.gaf && gzip union4.gaf
```
