#!/usr/bin/env python3

# SPDX-FileCopyrightText: (C) 2022 - 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0

import os
import time
import json
import tests.ui.common_ui_test_utils as common
from tests.ui.browser import Browser
from scene_common.rest_client import RESTClient

from scene_common.mqtt import PubSub
from scene_common.timestamp import get_iso_time

GOOD_DATA_PATH = os.path.join(os.path.dirname(os.path.realpath(__file__)), "test_media/good_data.txt")
SENSOR_NAME = "Scene_Sensor_to_be_Deleted"
SENSOR_ID = "scene_sensor_to_be_deleted"
SENSOR_TYPE_CHOICES = ["entire_scene", "circle", "triangle"]
is_receiving_message = False

def on_connect(mqttc, obj, flags, rc):
    print("Connected!")

def eventReceived(pahoClient, userdata, message):
    global is_receiving_message
    print(f"Message received from sensor {SENSOR_NAME}!")
    is_receiving_message = True

def verify_message_mqtt(client):
    global is_receiving_message
    is_receiving_message = False
    current_line = 0
    with open(GOOD_DATA_PATH, "r") as data:
        for line in data:
            if line.startswith("#"):
                continue
            jdata = json.loads(line.strip())
            camera_id = jdata["id"]
            jdata["timestamp"] = get_iso_time()
            line = json.dumps(jdata)

            print(f"Sending frame {current_line} id {camera_id}")
            client.publish(PubSub.formatTopic(PubSub.DATA_CAMERA, camera_id=camera_id), line.strip())
            time.sleep(1 / 10)
            current_line += 1
    return is_receiving_message

def getSensorUid(rest, sensor_name):
    res = rest.getSensors({"name": sensor_name})
    assert res["results"], f"getSensors REST call hasn't returned any results for {sensor_name}!"
    return res["results"][0]["uid"]

def test_create_and_delete_sensor_mqtt(params, record_xml_attribute):
    """! This function creates a sensor via UI, verifies event reception via MQTT,
    deletes the sensor, and ensures no events are received after deletion.

    @returns exit_code 0 on success, non-zero on failure
    """
    TEST_NAME = "NEX-T10432"
    record_xml_attribute("name", TEST_NAME)
    print(f"Executing: {TEST_NAME}")

    scene_name = common.TEST_SCENE_NAME
    exit_code = 6

    rest = RESTClient(params["resturl"], rootcert=params["rootcert"])
    assert rest.authenticate(params["user"], params["password"])

    try:
        browser = Browser()
        client = PubSub(params["auth"], None, params["rootcert"],
                        params["broker_url"], params["broker_port"])
        client.connect()
        client.loopStart()

        assert common.check_page_login(browser, params)
        assert common.check_db_status(browser)
        print("Logged in")

        assert common.navigate_to_scene(browser, scene_name)

        for sensor_type in SENSOR_TYPE_CHOICES:
            print(f"\n=== Executing test for {sensor_type} sensor... ===")
            assert common.create_sensor_from_scene(browser, SENSOR_ID, SENSOR_NAME, scene_name)

            if sensor_type == "circle":
                common.open_scene_manage_sensors_tab(browser)
                assert common.create_circle_sensor(browser)

            elif sensor_type == "triangle":
                common.open_scene_manage_sensors_tab(browser)
                assert common.create_triangle_sensor(browser)

            sensor_uid = getSensorUid(rest, SENSOR_NAME)
            topic = PubSub.formatTopic(PubSub.EVENT, region_type="region", event_type="objects",
                                       scene_id=common.TEST_SCENE_ID, region_id=sensor_uid)
            client.addCallback(topic, eventReceived)

            assert common.verify_sensor_under_scene(browser, [SENSOR_NAME])

            # Modify sensor if needed (not implemented here, placeholder)
            # assert common.modify_sensor(browser)
            # assert common.verify_sensor_under_scene(browser, [SENSOR_NAME])

            sensor_uid_check = getSensorUid(rest, SENSOR_NAME)
            assert sensor_uid_check == sensor_uid, f"Sensor UID mismatch! Before: {sensor_uid}, After: {sensor_uid_check}"

            print("Events should be received from the sensor...")
            message_received = verify_message_mqtt(client)
            assert message_received, f"No events received from {sensor_type} sensor!"
            exit_code -= 1

            # Delete sensor
            assert common.delete_sensor(browser, SENSOR_NAME)
            assert not common.verify_sensor_under_scene(browser, [SENSOR_NAME])

            print("Events should not be received from the sensor because it was deleted...")
            message_received = verify_message_mqtt(client)
            assert not message_received, f"Events still received from deleted {sensor_type} sensor!"
            exit_code -= 1

        client.loopStop()
        assert client.isConnected()
        if exit_code != 0:
            print("Received unexpected message from some sensors!")
        browser.close()

    finally:
        common.record_test_result(TEST_NAME, exit_code)

    assert exit_code == 0
    return
