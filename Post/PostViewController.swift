import UIKit
import PhotosUI
import ParseSwift
import Photos
import CoreLocation
import UniformTypeIdentifiers
import ImageIO

class PostViewController: UIViewController {

    @IBOutlet weak var shareButton: UIBarButtonItem!
    @IBOutlet weak var captionTextField: UITextField!
    @IBOutlet weak var previewImageView: UIImageView!

    private var pickedImage: UIImage?
    private var pickedLocationName: String?
    
    private var locationManager: CLLocationManager?
    private var lastKnownCaptureLocation: CLLocation?

    // call this once (e.g. in viewDidLoad)
    private func setupLocationManager() {
        let lm = CLLocationManager()
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyBest
        self.locationManager = lm
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        shareButton.isEnabled = false
        setupLocationManager()
    }

    func extractGPS(from url: URL) -> CLLocation? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary),
              let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, options as CFDictionary) as? [String: Any],
              let gps = metadata[kCGImagePropertyGPSDictionary as String] as? [String: Any],
              let lat = gps[kCGImagePropertyGPSLatitude as String] as? Double,
              let lon = gps[kCGImagePropertyGPSLongitude as String] as? Double
        else { return nil }

        let latRef = (gps[kCGImagePropertyGPSLatitudeRef as String] as? String)?.uppercased() ?? "N"
        let lonRef = (gps[kCGImagePropertyGPSLongitudeRef as String] as? String)?.uppercased() ?? "E"

        let finalLat = (latRef == "S") ? -lat : lat
        let finalLon = (lonRef == "W") ? -lon : lon

        return CLLocation(latitude: finalLat, longitude: finalLon)
    }
    
    func reverseGeocode(location: CLLocation, completion: @escaping (String?) -> Void) {
        let geocoder = CLGeocoder()

        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if let error = error {
                print("Reverse geocode failed: \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let placemark = placemarks?.first else {
                completion(nil)
                return
            }

            var parts: [String] = []

            if let city = placemark.locality {
                parts.append(city)
            }

            if let state = placemark.administrativeArea {
                parts.append(state)
            }

            if let country = placemark.country {
                parts.append(country)
            }

            completion(parts.joined(separator: ", "))
        }
    }
    
    @IBAction func onPickedImageTapped(_ sender: UIBarButtonItem) {
        
        var config = PHPickerConfiguration()

        config.filter = .images

        config.preferredAssetRepresentationMode = .current

        config.selectionLimit = 1

        let picker = PHPickerViewController(configuration: config)

        picker.delegate = self

        present(picker, animated: true)
    }

    @IBAction func onShareTapped(_ sender: Any) {
        view.endEditing(true)

        guard let image = pickedImage,
              let imageData = image.jpegData(compressionQuality: 0.7) else {
            return
        }

        let imageFile = ParseFile(name: "image.jpg", data: imageData)

        var post = Post()

        post.imageFile = imageFile
        
        post.caption = captionTextField.text

        post.locationName = pickedLocationName
        
        post.user = User.current

        post.save { [weak self] result in

            DispatchQueue.main.async {
                switch result {
                case .success(let post):
                    print("✅ Post Saved! \(post)")

                    self?.captionTextField.text = ""
                    self?.previewImageView.image = nil
                    self?.pickedImage = nil
                    self?.pickedLocationName = nil
                    self?.shareButton.isEnabled = false

                    self?.tabBarController?.selectedIndex = 0

                case .failure(let error):
                    self?.showAlert(description: error.localizedDescription)
                }
            }
        }
    }

    @IBAction func onTakePhotoTapped(_ sender: Any) {
        // Make sure the user's camera is available
        // NOTE: Camera only available on physical iOS device, not available on simulator.
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            print("❌📷 Camera not available")
            return
        }

        // Request permission if needed
            if let status = locationManager?.authorizationStatus {
                if status == .notDetermined {
                    locationManager?.requestWhenInUseAuthorization()
                }
            }

            // Start updates so we have a location near capture time
            lastKnownCaptureLocation = nil
            locationManager?.startUpdatingLocation()

            let imagePicker = UIImagePickerController()
            imagePicker.sourceType = .camera
            imagePicker.allowsEditing = false
            imagePicker.delegate = self
            present(imagePicker, animated: true)
        }
}

extension PostViewController: PHPickerViewControllerDelegate {

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        guard let result = results.first else { return }
        let provider = result.itemProvider

        // Load image for preview
        if provider.canLoadObject(ofClass: UIImage.self) {
            provider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                guard let self = self else { return }
                guard let image = object as? UIImage else { return }

                DispatchQueue.main.async {
                    self.previewImageView.image = image
                    self.pickedImage = image
                    self.pickedLocationName = nil
                    self.shareButton.isEnabled = true
                }
            }
        }

        // ARTICLE METHOD: load file representation for EXIF
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, error in
                guard let self = self else { return }
                guard let url = url else { return }

                // Copy to a stable temp location
                let tmpURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension)

                do {
                    try FileManager.default.copyItem(at: url, to: tmpURL)
                } catch {
                    // If copy fails, fallback to original url
                }

                let gpsSourceURL = (FileManager.default.fileExists(atPath: tmpURL.path)) ? tmpURL : url

                if let location = self.extractGPS(from: gpsSourceURL) {
                    self.reverseGeocode(location: location) { placemarkString in
                        DispatchQueue.main.async {
                            self.pickedLocationName = placemarkString
                            print("EXIF Location: \(placemarkString ?? "Unknown")")
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.pickedLocationName = nil
                        print("No GPS EXIF in selected image")
                    }
                }
            }
        }
    }
}

extension PostViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    // Delegate method that's called when user finishes picking image (photo library or camera)
    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)

        // Prefer original image (allowsEditing = false)
        guard let image = info[.originalImage] as? UIImage else {
            print("No image found")
            return
        }

        // Set UI and store image
        previewImageView.image = image
        pickedImage = image
        shareButton.isEnabled = true
        pickedLocationName = nil

        // 1) Try imageURL -> EXIF (same as before)
        if let imageURL = info[.imageURL] as? URL {
            // Copy to stable temp location
            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(imageURL.pathExtension)
            do {
                try FileManager.default.copyItem(at: imageURL, to: tmpURL)
            } catch {
                // fallback if copy fails
            }
            let gpsSourceURL = (FileManager.default.fileExists(atPath: tmpURL.path)) ? tmpURL : imageURL

            if let location = extractGPS(from: gpsSourceURL) {
                reverseGeocode(location: location) { [weak self] placemarkString in
                    DispatchQueue.main.async {
                        self?.pickedLocationName = placemarkString
                        self?.captionTextField.placeholder = placemarkString ?? "Location unavailable"
                        print("Camera EXIF Location: \(placemarkString ?? "Unknown")")
                        // stop location updates (we have what we need)
                        self?.locationManager?.stopUpdatingLocation()
                    }
                }
                return
            } else {
                print("No GPS EXIF in camera image (file)")
            }
        }

        // 2) Try mediaMetadata GPS dictionary (possible when no file URL)
        if let metadata = info[.mediaMetadata] as? [String: Any],
           let gps = metadata["{GPS}"] as? [String: Any],
           let lat = gps["Latitude"] as? Double,
           let lon = gps["Longitude"] as? Double {

            let latRef = (gps["LatitudeRef"] as? String ?? "N").uppercased()
            let lonRef = (gps["LongitudeRef"] as? String ?? "E").uppercased()
            let finalLat = (latRef == "S") ? -lat : lat
            let finalLon = (lonRef == "W") ? -lon : lon

            let coord = CLLocation(latitude: finalLat, longitude: finalLon)
            reverseGeocode(location: coord) { [weak self] placemarkString in
                DispatchQueue.main.async {
                    self?.pickedLocationName = placemarkString
                    self?.captionTextField.placeholder = placemarkString ?? "Location unavailable"
                    print("Camera metadata GPS -> \(placemarkString ?? "Unknown")")
                    self?.locationManager?.stopUpdatingLocation()
                }
            }
            return
        }

        // 3) FALLBACK: use device location collected by CLLocationManager
        if let recent = lastKnownCaptureLocation {
            reverseGeocode(location: recent) { [weak self] placemarkString in
                DispatchQueue.main.async {
                    self?.pickedLocationName = placemarkString
                    self?.captionTextField.placeholder = placemarkString ?? "Location unavailable"
                    print("Camera device location -> \(placemarkString ?? "Unknown")")
                    self?.locationManager?.stopUpdatingLocation()
                }
            }
            return
        }

        // nothing found
        print("No imageURL available from camera capture and no GPS metadata; device location also unavailable")
        captionTextField.placeholder = "Location unavailable"
        locationManager?.stopUpdatingLocation()
    }
}

extension PostViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // keep the last good location (timestamped)
        if let loc = locations.last {
            lastKnownCaptureLocation = loc
            // don't stop here — keep updating until photo is taken,
            // but you could stop after first fix if you prefer:
            // manager.stopUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager error: \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            print("Location authorized")
        case .denied, .restricted:
            print("Location not authorized")
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }
}
