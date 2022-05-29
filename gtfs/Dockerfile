FROM python:3

RUN pip install requests

WORKDIR /gtfs

COPY bboxes.csv download_gtfs_feeds.py /gtfs/

CMD [ "/gtfs/download_gtfs_feeds.py" ]