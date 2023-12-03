using System.Collections;
using System.Collections.Generic;
using UnityEngine;


public class CameraController : MonoBehaviour {

    public float sensivity = 0.075f;
    private Vector3 lastMousePos;
    private bool isRightClicked = false;
    public float camSpeed = 10.0f;

    public void Start() {
        QualitySettings.vSyncCount = 1;
    }

    void LateUpdate() { 
        if (Input.GetMouseButton(1) && !isRightClicked) {
            isRightClicked = true;
            lastMousePos = Input.mousePosition;
            Cursor.lockState = CursorLockMode.Confined;
        }
        else if (Input.GetMouseButton(1) && isRightClicked) {
            Vector3 mousePos = Input.mousePosition;
            Vector3 diff = mousePos - lastMousePos;

            Vector3 euler = transform.eulerAngles;
            euler.x -= diff.y * sensivity;
            euler.y += diff.x * sensivity;

            Mathf.Clamp(euler.x, -80, 80);
            Mathf.Clamp(euler.y, -80, 80);

            transform.eulerAngles = euler;

            lastMousePos = Input.mousePosition;
        }
        else {
            isRightClicked = false;
            Cursor.lockState = CursorLockMode.None;
        }
    }

    private void Update() {
        float delta = Time.deltaTime;

        // W S movement 
        if (Input.GetKey(KeyCode.W)) {
            transform.position += transform.forward * camSpeed * delta;
        }
        else if (Input.GetKey(KeyCode.S)) {
            transform.position -= transform.forward * camSpeed * delta;
        }

        // A D movement
        if (Input.GetKey(KeyCode.D)) {
            transform.position += transform.right * camSpeed * delta;
        }
        else if (Input.GetKey(KeyCode.A)) {
            transform.position -= transform.right * camSpeed * delta;
        }

        // Ascend and descent using space and shift
        if (Input.GetKey(KeyCode.Space)) {
            transform.position += new Vector3(0, camSpeed, 0) * delta;
        }
        else if (Input.GetKey(KeyCode.LeftShift)) {
            transform.position += new Vector3(0, -camSpeed, 0) * delta;
        }
    }
}
