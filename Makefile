CITIES = Aachen Aarhus Adelaide Albuquerque Alexandria Amsterdam Antwerpen Arnhem Auckland Augsburg Austin Baghdad \
				Baku Balaton Bamberg Bangkok Barcelona Basel Beijing Beirut Berkeley Berlin Bern Bielefeld Birmingham Bochum \
				Bogota Bombay Bonn Bordeaux Boulder BrandenburgHavel Braunschweig Bremen Bremerhaven Brisbane Bristol Brno \
				Bruegge Bruessel Budapest BuenosAires Cairo Calgary Cambridge CambridgeMa Canberra CapeTown Chemnitz Chicago \
				ClermontFerrand Colmar Copenhagen Cork Corsica Corvallis Cottbus Cracow CraterLake Curitiba Cusco Dallas \
				Darmstadt Davis DenHaag Denver Dessau Dortmund Dresden Dublin Duesseldorf Duisburg Edinburgh Eindhoven Emden \
				Erfurt Erlangen Eugene Flensburg FortCollins Frankfurt FrankfurtOder Freiburg Gdansk Genf Gent Gera Glasgow \
				Gliwice Goerlitz Goeteborg Goettingen Graz Groningen Halifax Halle Hamburg Hamm Hannover Heilbronn Helsinki \
				Hertogenbosch Huntsville Innsbruck Istanbul Jena Jerusalem Johannesburg Kaiserslautern Karlsruhe Kassel \
				Katowice Kaunas Kiel Kiew Koblenz Koeln Konstanz LakeGarda LaPaz LaPlata Lausanne Leeds Leipzig Lima Linz \
				Lisbon Liverpool Ljubljana Lodz London Luebeck Luxemburg Lyon Maastricht Madison Madrid Magdeburg Mainz \
				Malmoe Manchester Mannheim Marseille Melbourne Memphis MexicoCity Miami Minsk Moenchengladbach Montevideo \
				Montpellier Montreal Moscow Muenchen Muenster NewDelhi NewOrleans NewYork Nuernberg Oldenburg Oranienburg \
				Orlando Oslo Osnabrueck Ostrava Ottawa Paderborn Palma PaloAlto Paris Perth Philadelphia PhnomPenh Portland \
				PortlandME Porto PortoAlegre Potsdam Poznan Prag Providence Regensburg Riga RiodeJaneiro Rostock Rotterdam \
				Ruegen Saarbruecken Sacramento Saigon Salzburg SanFrancisco SanJose SanktPetersburg SantaBarbara SantaCruz \
				Santiago Sarajewo Schwerin Seattle Seoul Sheffield Singapore Sofia Stockholm Stockton Strassburg Stuttgart \
				Sucre Sydney Szczecin Tallinn Tehran Tilburg Tokyo Toronto Toulouse Trondheim Tucson Turin UlanBator Ulm \
				Usedom Utrecht Vancouver Victoria WarenMueritz Warsaw WashingtonDC Waterloo Wien Wroclaw Wuerzburg Wuppertal \
				Zagreb Zuerich

.DEFAULT_GOAL := help

help:
	@echo "Try 'make Amsterdam'"
	@echo "Docker must be installed"
	@echo "'make list' for all available metro areas."

list:
	@echo ${CITIES}

.base_url:
	@echo "Using default base URL, override this if you want to host this for the open internet!"
	echo 'http://localhost:8080' > $@

%.osm.pbf:
	@echo "Downloading $@ from BBBike.";
	@echo "\n\nConsider donating to BBBike to help cover hosting! https://extract.bbbike.org/community.html\n\n"
	wget -U headway/1.0 -O $@ "https://download.bbbike.org/osm/bbbike/$(basename $(basename $@))/$@" || rm $@

%.bbox:
	@echo "Extracting bounding box for $(basename $@)"
	grep "$(basename $@):" gtfs/bboxes.csv > $@
	perl -i.bak -pe 's/$(basename $@)://' $@

%.gtfs.tar: %.bbox
	cp $(basename $(basename $@)).bbox ./gtfs/city.bbox
	docker build ./gtfs --tag headway_gtfs_download
	-docker volume rm -f headway_gtfs_build || echo "Volume does not exist!"
	docker volume create headway_gtfs_build
	docker run --memory=6G -it --rm \
		-v headway_gtfs_build:/gtfs_volume \
		headway_gtfs_download \
		python3 download_gtfs_feeds.py $(basename $(basename $@))
	docker run --rm \
		-v headway_gtfs_build:/gtfs_volume \
		ubuntu:jammy \
		bash -c "cd /gtfs_volume && ls *.zip | tar -cf gtfs.tar --files-from -"
	docker run --rm -d --name headway_gtfs_ephemeral_busybox \
		-v headway_gtfs_build:/gtfs_volume \
		busybox \
		sleep 1000
	-docker ps -aqf "name=headway_gtfs_ephemeral_busybox" > .gtfs_download_cid
	bash -c 'docker cp $$(<.gtfs_download_cid):/gtfs_volume/gtfs.tar $@'
	-bash -c 'docker kill $$(<.gtfs_download_cid) || echo "container is not running"'

%.mbtiles: %.osm.pbf
	@echo "Building MBTiles $(basename $@)"
	mkdir -p ./.tmp_mbtiles
	cp $(basename $@).osm.pbf ./.tmp_mbtiles/data.osm.pbf
	docker volume create headway_mbtiles_build || echo "Volume already exists"
	docker build ./mbtiles/bootstrap --tag headway_mbtiles_bootstrap
	docker run --rm -v headway_mbtiles_build:/data headway_mbtiles_bootstrap
	docker run --memory=6G --rm -e JAVA_TOOL_OPTIONS="-Xmx8g" \
		-v headway_mbtiles_build:/data \
		-v "${PWD}/.tmp_mbtiles":/input_volume \
		ghcr.io/onthegomap/planetiler:latest \
		--osm-path=/input_volume/data.osm.pbf \
		--download \
		--force
	docker ps -aqf "name=headway_mbtiles_ephemeral_busybox" > .mbtiles_cid
	-bash -c 'docker kill $$(<.mbtiles_cid) || echo "container is not running"'
	-bash -c 'docker rm $$(<.mbtiles_cid) || echo "container does not exist"'
	docker run -d --name headway_mbtiles_ephemeral_busybox -v headway_mbtiles_build:/headway_mbtiles_build busybox sleep 1000
	docker ps -aqf "name=headway_mbtiles_ephemeral_busybox" > .mbtiles_cid
	bash -c 'docker cp $$(<.mbtiles_cid):/headway_mbtiles_build/output.mbtiles $@'
	-bash -c 'docker kill $$(<.mbtiles_cid) || echo "container is not running"'
	-bash -c 'docker rm $$(<.mbtiles_cid) || echo "container does not exist"'

%.nominatim.tgz: %.nominatim_image
	@echo "Bootstrapping geocoding index for $(basename $(basename $@))."
	mkdir -p ./.tmp_geocoder
	rm -rf ./.tmp_geocoder/*
	cp $(basename $(basename $@)).osm.pbf ./geocoder/nominatim/data.osm.pbf
	docker volume rm -f headway_geocoder_build || echo "Volume does not exist!"
	docker volume create headway_geocoder_build
	docker build ./geocoder/nominatim --tag headway_nominatim
	docker run --memory=6G -it --rm \
		-v headway_geocoder_build:/tmp_volume \
		-v "${PWD}/.tmp_geocoder":/data_volume \
		-e PBF_PATH=/data_volume/data.osm.pbf \
		headway_nominatim \
		/jobs/import_wait_dump.sh
	docker ps -aqf "name=headway_geocoder_ephemeral_busybox" > .nominatim_cid
	-bash -c 'docker kill $$(<.nominatim_cid) || echo "container is not running"'
	-bash -c 'docker rm $$(<.nominatim_cid) || echo "container does not exist"'
	docker run -d --rm --name headway_geocoder_ephemeral_busybox -v headway_geocoder_build:/headway_geocoder_build busybox sleep 1000
	docker ps -aqf "name=headway_geocoder_ephemeral_busybox" > .nominatim_cid
	bash -c 'docker cp $$(<.nominatim_cid):/headway_geocoder_build/nominatim ./.tmp_geocoder/nominatim'
	-bash -c 'docker kill $$(<.nominatim_cid) || echo "container is not running"'
	-bash -c 'docker rm $$(<.nominatim_cid) || echo "container does not exist"'
	tar -C ./.tmp_geocoder -czf $@ nominatim
	rm -rf ./.tmp_geocoder/*

%.photon_image: %.nominatim.tgz
	@echo "Importing data into photon and building image for $(basename $@)."
	cp $(basename $@).nominatim.tgz ./geocoder/photon/data.nominatim.tgz
	docker build ./geocoder/photon --tag headway_photon

%.tileserver_image: %.mbtiles
	@echo "Building tileserver image for $(basename $@)."
	cp $(basename $@).mbtiles ./tileserver/tiles.mbtiles
	docker build ./tileserver --tag headway_tileserver

%.nominatim_image: %.osm.pbf
	mkdir -p ./.tmp_geocoder
	rm -rf ./.tmp_geocoder/*
	cp $(basename $(basename $@)).osm.pbf ./geocoder/nominatim/data.osm.pbf
	docker build ./geocoder/nominatim --tag headway_nominatim

%.graph.tar: %.osm.pbf %.gtfs.tar
	@echo "Pre-generating graphhopper graph for $(basename $(basename $@))."
	docker build ./graphhopper --tag headway_graphhopper_build_image
	mkdir -p ./.tmp_graphhopper
	rm -rf ./.tmp_graphhopper/*
	cp $(basename $(basename $@)).osm.pbf ./.tmp_graphhopper/data.osm.pbf
	-docker volume rm -f headway_graphhopper_build || echo "Volume does not exist!"
	docker volume create headway_graphhopper_build
	docker run -d --rm --name headway_graphhopper_ephemeral_busybox_build \
		-v headway_graphhopper_build:/headway_graphhopper_build \
		alpine:3 \
		sleep 1000
	docker ps -aqf "name=headway_graphhopper_ephemeral_busybox_build" > .graphhopper_build_cid
	bash -c 'docker cp $(basename $(basename $@)).osm.pbf $$(<.graphhopper_build_cid):/headway_graphhopper_build/data.osm.pbf'
	bash -c 'docker cp $(basename $(basename $@)).gtfs.tar $$(<.graphhopper_build_cid):/headway_graphhopper_build/gtfs.tar'
	-bash -c 'docker kill $$(<.graphhopper_build_cid) || echo "container is not running"'
	docker run --memory=8G -it --rm \
		-v headway_graphhopper_build:/graph_volume \
		headway_graphhopper_build_image \
		/graphhopper/startup.sh \
		-Xmx8g \
		-Xms8g \
		-jar \
		/graphhopper/graphhopper-web-5.3.jar \
		import \
		/graphhopper/config.yaml
	-docker ps -aqf "name=headway_graphhopper_ephemeral_busybox_build" > .graphhopper_build_cid
	-bash -c 'docker kill $$(<.graphhopper_build_cid) || echo "container is not running"'
	docker run --rm \
		-v headway_graphhopper_build:/headway_graphhopper_build \
		alpine:3 \
		/bin/sh -c 'rm -f /headway_graphhopper_build/graph.tar && cd /headway_graphhopper_build && tar -cf graph.tar *'
	docker run -d --rm --name headway_graphhopper_ephemeral_busybox_build \
		-v headway_graphhopper_build:/headway_graphhopper_build \
		busybox \
		sleep 1000
	docker ps -aqf "name=headway_graphhopper_ephemeral_busybox_build" > .graphhopper_build_cid
	bash -c 'docker cp $$(<.graphhopper_build_cid):/headway_graphhopper_build/graph.tar $@'
	-bash -c 'docker kill $$(<.graphhopper_build_cid) || echo "container is not running"'
	rm -rf ./.tmp_graphhopper/*

%.nginx_image: .base_url %.bbox
	cp .base_url web/
	cp $(basename $@).bbox web/bbox.txt
	docker build ./web --tag headway_nginx

%.tag_images: %.tileserver_image %.photon_image %.nginx_image %.nominatim_image graphhopper_image
	@echo "Tagging images"

%.graphhopper_volume: %.graph.tar graphhopper_image
	@echo "Create volume, then delete, then create, to force failures if the volume is in use."
	-docker volume create headway_graphhopper_vol
	docker volume rm -f headway_graphhopper_vol
	docker volume create headway_graphhopper_vol

	docker run -d --rm --name headway_graphhopper_ephemeral_busybox_tag \
		-v headway_graphhopper_vol:/headway_graphhopper \
		alpine:3 \
		sleep 1000

	-docker ps -aqf "name=headway_graphhopper_ephemeral_busybox_tag" > .graphhopper_cid
	bash -c 'docker cp $(basename $@).graph.tar $$(<.graphhopper_cid):/headway_graphhopper/graph.tar'
	-bash -c 'docker kill $$(<.graphhopper_cid) || echo "container is not running"'

	docker run --rm \
		-v headway_graphhopper_vol:/headway_graphhopper \
		alpine:3 \
		/bin/sh -c 'cd /headway_graphhopper && tar -xvf graph.tar && rm graph.tar'

%.tag_volumes: %.graphhopper_volume
	@echo "Tagged volumes"

$(filter %,$(CITIES)): %: %.osm.pbf %.nominatim.tgz %.mbtiles %.graph.tar %.gtfs.tar %.tag_images %.tag_volumes
	@echo "Building $@"

clean:
	rm -rf ./*.nominatim.tgz
	rm -rf ./*.mbtiles
	rm -rf ./.tmp_mbtiles/tmp
	rm -rf ./.tmp_mbtiles/data.osm.pbf
	rm -rf ./.tmp_geocoder/*
	rm -rf ./.*_cid

%.up: % %.osm.pbf %.nominatim.tgz %.mbtiles %.graph.tar %.gtfs.tar %.tag_images %.tag_volumes
	docker-compose kill || echo "Containers not up"
	docker-compose down || echo "Containers dont exist"
	docker-compose up -d

# Don't clean base URL because that's a user config option.
clean_all: clean
	rm -rf ./*.osm.pbf
	rm -rf ./.tmp_mbtiles/*

graphhopper_image:
	docker build ./graphhopper --tag headway_graphhopper