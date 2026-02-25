import json
import time
from azure.eventhub import EventHubProducerClient, EventData
from azure.identity import DefaultAzureCredential

credential = DefaultAzureCredential()
producer = EventHubProducerClient(
    fully_qualified_namespace="ehns-airline-dlt-dev-uks.servicebus.windows.net",
    eventhub_name="airline-events",
    credential=credential
)

bad_events = [
    # Missing MONTH
    {"MONTH": None, "DAY_OF_MONTH": "15", "DAY_OF_WEEK": "3", "OP_UNIQUE_CARRIER": "AA",
     "TAIL_NUM": "N123AA", "OP_CARRIER_FL_NUM": "100", "ORIGIN_AIRPORT_ID": "12478",
     "ORIGIN": "JFK", "ORIGIN_CITY_NAME": "New York, NY", "DEST_AIRPORT_ID": "12892",
     "DEST": "LAX", "DEST_CITY_NAME": "Los Angeles, CA", "CRS_DEP_TIME": "800",
     "DEP_TIME": "805", "DEP_DELAY_NEW": "5", "DEP_DEL15": "0", "DEP_TIME_BLK": "0800-0859",
     "CRS_ARR_TIME": "1100", "ARR_TIME": "1110", "ARR_DELAY_NEW": "10",
     "ARR_TIME_BLK": "1100-1159", "CANCELLED": "0", "CANCELLATION_CODE": "",
     "CRS_ELAPSED_TIME": "180", "ACTUAL_ELAPSED_TIME": "185", "DISTANCE": "2475",
     "DISTANCE_GROUP": "10", "CARRIER_DELAY": "", "WEATHER_DELAY": "", "NAS_DELAY": "",
     "SECURITY_DELAY": "", "LATE_AIRCRAFT_DELAY": "", "_row_num": "BAD_001"},

    # Missing ORIGIN
    {"MONTH": "3", "DAY_OF_MONTH": "20", "DAY_OF_WEEK": "5", "OP_UNIQUE_CARRIER": "UA",
     "TAIL_NUM": "N456UA", "OP_CARRIER_FL_NUM": "200", "ORIGIN_AIRPORT_ID": "",
     "ORIGIN": None, "ORIGIN_CITY_NAME": "", "DEST_AIRPORT_ID": "13930",
     "DEST": "ORD", "DEST_CITY_NAME": "Chicago, IL", "CRS_DEP_TIME": "1400",
     "DEP_TIME": "1420", "DEP_DELAY_NEW": "20", "DEP_DEL15": "1", "DEP_TIME_BLK": "1400-1459",
     "CRS_ARR_TIME": "1700", "ARR_TIME": "1715", "ARR_DELAY_NEW": "15",
     "ARR_TIME_BLK": "1700-1759", "CANCELLED": "0", "CANCELLATION_CODE": "",
     "CRS_ELAPSED_TIME": "180", "ACTUAL_ELAPSED_TIME": "175", "DISTANCE": "1846",
     "DISTANCE_GROUP": "8", "CARRIER_DELAY": "20", "WEATHER_DELAY": "0", "NAS_DELAY": "0",
     "SECURITY_DELAY": "0", "LATE_AIRCRAFT_DELAY": "0", "_row_num": "BAD_002"},

    # Missing DEST
    {"MONTH": "3", "DAY_OF_MONTH": "25", "DAY_OF_WEEK": "3", "OP_UNIQUE_CARRIER": "DL",
     "TAIL_NUM": "N789DL", "OP_CARRIER_FL_NUM": "300", "ORIGIN_AIRPORT_ID": "10397",
     "ORIGIN": "ATL", "ORIGIN_CITY_NAME": "Atlanta, GA", "DEST_AIRPORT_ID": "",
     "DEST": None, "DEST_CITY_NAME": "", "CRS_DEP_TIME": "600",
     "DEP_TIME": "600", "DEP_DELAY_NEW": "0", "DEP_DEL15": "0", "DEP_TIME_BLK": "0600-0659",
     "CRS_ARR_TIME": "800", "ARR_TIME": "755", "ARR_DELAY_NEW": "0",
     "ARR_TIME_BLK": "0800-0859", "CANCELLED": "0", "CANCELLATION_CODE": "",
     "CRS_ELAPSED_TIME": "120", "ACTUAL_ELAPSED_TIME": "115", "DISTANCE": "760",
     "DISTANCE_GROUP": "4", "CARRIER_DELAY": "", "WEATHER_DELAY": "", "NAS_DELAY": "",
     "SECURITY_DELAY": "", "LATE_AIRCRAFT_DELAY": "", "_row_num": "BAD_003"},

    # Missing ALL THREE
    {"MONTH": None, "DAY_OF_MONTH": "1", "DAY_OF_WEEK": "1", "OP_UNIQUE_CARRIER": "WN",
     "TAIL_NUM": "N000WN", "OP_CARRIER_FL_NUM": "999", "ORIGIN_AIRPORT_ID": "",
     "ORIGIN": None, "ORIGIN_CITY_NAME": "", "DEST_AIRPORT_ID": "",
     "DEST": None, "DEST_CITY_NAME": "", "CRS_DEP_TIME": "0",
     "DEP_TIME": "", "DEP_DELAY_NEW": "", "DEP_DEL15": "", "DEP_TIME_BLK": "",
     "CRS_ARR_TIME": "0", "ARR_TIME": "", "ARR_DELAY_NEW": "",
     "ARR_TIME_BLK": "", "CANCELLED": "1", "CANCELLATION_CODE": "A",
     "CRS_ELAPSED_TIME": "", "ACTUAL_ELAPSED_TIME": "", "DISTANCE": "",
     "DISTANCE_GROUP": "", "CARRIER_DELAY": "", "WEATHER_DELAY": "", "NAS_DELAY": "",
     "SECURITY_DELAY": "", "LATE_AIRCRAFT_DELAY": "", "_row_num": "BAD_004"},
]

batch = producer.create_batch()
for i, event in enumerate(bad_events):
    batch.add(EventData(json.dumps(event)))
    print(f"Added bad event {i+1}: _row_num={event['_row_num']}")

producer.send_batch(batch)
print(f"\nSent {len(bad_events)} bad events to airline-events")
producer.close()