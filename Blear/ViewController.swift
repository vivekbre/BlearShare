import UIKit
import Photos
import FDTake
import IIDelayedAction
import JGProgressHUD
import CoreImage

let IS_IPAD = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiom.pad
let IS_IPHONE = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiom.phone
let SCREEN_WIDTH = UIScreen.main.bounds.size.width
let SCREEN_HEIGHT = UIScreen.main.bounds.size.height
let IS_LARGE_SCREEN = IS_IPHONE && max(SCREEN_WIDTH, SCREEN_HEIGHT) >= 736.0

final class ViewController: UIViewController {
	var sourceImage: UIImage?
	var delayedAction: IIDelayedAction?
	var blurAmount: Float = 0
	let stockImages = Bundle.main.urls(forResourcesWithExtension: "jpg", subdirectory: "Bundled Photos")!
	lazy var randomImageIterator: AnyIterator<URL> = self.stockImages.uniqueRandomElement()
	
	var filters = ["CIColorClamp","CIColorPolynomial","CIVibrance","CISepiaTone","CIVignette","CIUnsharpMask","CIPhotoEffectNoir","CIColorPosterize","CIPixellate","CIGaussianBlur","CIGloom","CICrystallize","CIComicEffect"]
	var context: CIContext!
	var index = 0
	var currentFilter: CIFilter!

	lazy var imageView = with(UIImageView()) {
		$0.image = UIImage(color: .black, size: view.frame.size)
		$0.contentMode = .scaleAspectFill
		$0.clipsToBounds = true
		$0.frame = view.bounds
	}

	lazy var slider = with(UISlider()) {
		let SLIDER_MARGIN: CGFloat = 120
		$0.frame = CGRect(x: 0, y: 0, width: view.frame.size.width - SLIDER_MARGIN, height: view.frame.size.height)
		$0.minimumValue = 0
		$0.maximumValue = 100
		$0.value = blurAmount
		$0.isContinuous = true
		$0.setThumbImage(UIImage(named: "SliderThumb")!, for: .normal)
		$0.autoresizingMask = [
			.flexibleWidth,
			.flexibleTopMargin,
			.flexibleBottomMargin,
			.flexibleLeftMargin,
			.flexibleRightMargin
		]
		$0.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
	}

	override var canBecomeFirstResponder: Bool {
		return true
	}

	override var prefersStatusBarHidden: Bool {
		return true
	}

	override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
		if motion == .motionShake {
			randomImage()
		}
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		// This is to ensure that it always ends up with the current blur amount when the slider stops
		// since we're using `DispatchQueue.global().async` the order of events aren't serial
		delayedAction = IIDelayedAction({}, withDelay: 0.2)
		delayedAction?.onMainThread = false
		
		
		context = CIContext()
		
		self.imageView.isUserInteractionEnabled = true

		view.addSubview(imageView)
		
		let pinch = UIPinchGestureRecognizer(target: self, action: #selector(self.pinch(sender:)))
		self.imageView.addGestureRecognizer(pinch)
		
		let longPress = UILongPressGestureRecognizer(target: self, action: #selector(self.longPress(sender:)))
		self.imageView.addGestureRecognizer(longPress)
		
		
		let swipeRight = UISwipeGestureRecognizer(target: self, action:#selector(rightGesture(sender:)))
		swipeRight.direction = UISwipeGestureRecognizer.Direction.right
		self.view.addGestureRecognizer(swipeRight)
		
		
		let swiftLeft = UISwipeGestureRecognizer(target: self, action: #selector(leftGesture(sender:)))
		swiftLeft.direction = UISwipeGestureRecognizer.Direction.left
		self.view.addGestureRecognizer(swiftLeft)
		

		let TOOLBAR_HEIGHT: CGFloat = 80 + window.safeAreaInsets.bottom
		let toolbar = UIToolbar(frame: CGRect(x: 0, y: view.frame.size.height - TOOLBAR_HEIGHT, width: view.frame.size.width, height: TOOLBAR_HEIGHT))
		toolbar.autoresizingMask = .flexibleWidth
		toolbar.alpha = 0.6
		toolbar.tintColor = #colorLiteral(red: 0.98, green: 0.98, blue: 0.98, alpha: 1)

		// Remove background
		toolbar.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)
		toolbar.setShadowImage(UIImage(), forToolbarPosition: .any)

		// Gradient background
		let GRADIENT_PADDING: CGFloat = 40
		let gradient = CAGradientLayer()
		gradient.frame = CGRect(x: 0, y: -GRADIENT_PADDING, width: toolbar.frame.size.width, height: toolbar.frame.size.height + GRADIENT_PADDING)
		gradient.colors = [
			UIColor.clear.cgColor,
			UIColor.black.withAlphaComponent(0.1).cgColor,
			UIColor.black.withAlphaComponent(0.3).cgColor,
			UIColor.black.withAlphaComponent(0.4).cgColor
		]
		toolbar.layer.addSublayer(gradient)

		toolbar.items = [
			UIBarButtonItem(image: UIImage(named: "PickButton")!, target: self, action: #selector(pickImage), width: 20),
			.flexibleSpace,
			UIBarButtonItem(customView: slider),
			.flexibleSpace,
			UIBarButtonItem(image: UIImage(named: "SaveButton")!, target: self, action: #selector(saveImage), width: 20)
		]
		view.addSubview(toolbar)

		// Important that this is here at the end for the fading to work
		randomImage()
	}

	@objc
	func pickImage() {
		let fdTake = FDTakeController()
		fdTake.allowsVideo = false
		fdTake.didGetPhoto = { photo, _ in
			self.changeImage(photo)
		}
		fdTake.present()
	}
	
	@objc func pinch(sender:UIPinchGestureRecognizer) {
		if sender.state == .changed {
			let currentScale = self.imageView.frame.size.width / self.imageView.bounds.size.width
			var newScale = currentScale*sender.scale
			if newScale < 1 {
				newScale = 1
			}
			if newScale > 9 {
				newScale = 9
			}
			let transform = CGAffineTransform(scaleX: newScale, y: newScale)
			self.imageView.transform = transform
			sender.scale = 1
		}
			else if sender.state == .ended {
			UIView.animate(withDuration: 0.3, animations: {
				self.imageView.transform = CGAffineTransform.identity
			})
		}
	}
	
	@objc func longPress(sender: UILongPressGestureRecognizer) {
		if sender.state == .began {
			self.displayShareSheet(shareContent:imageView.image!)
		}
	}
	
	func displayShareSheet(shareContent:UIImage) {
		let activityViewController = UIActivityViewController(activityItems: [shareContent], applicationActivities: nil)
		present(activityViewController, animated: true, completion: {})
	}
	
	@objc func leftGesture(sender: UISwipeGestureRecognizer) {

		print("left")
		if(index < filters.count) {
		print(filters[index])
 		currentFilter = CIFilter(name: filters[index])
		let beginImage = CIImage(image: self.imageView.image!)
		currentFilter.setValue(beginImage, forKey: kCIInputImageKey)
		applyProcessing()
		if(index < filters.count) {
			index += 1
		} else {
			index = filters.count
		}
		} else {
			index = 0
		}
	}
	
	@objc func rightGesture(sender: UISwipeGestureRecognizer) {
		print("right")
		if(index > 0) {
		index -= 1
		currentFilter = CIFilter(name: filters[index])
		let beginImage = CIImage(image: self.imageView.image!)
		currentFilter.setValue(beginImage, forKey: kCIInputImageKey)
		applyProcessing()
		} else {
			index = 0
			self.blurAmount = 0
			self.updateImage()
		}
		
	}
	
	
	func applyProcessing() {
		guard let image = currentFilter.outputImage else { return }
		if let cgimg = context.createCGImage(image, from: image.extent) {
			let processedImage = UIImage(cgImage: cgimg)
			imageView.image = processedImage
		}
	}
	
	
	func blurImage(_ blurAmount: Float) -> UIImage {
		return UIImageEffects.imageByApplyingBlur(
			to: sourceImage,
			withRadius: CGFloat(blurAmount * (IS_LARGE_SCREEN ? 0.8 : 1.2)),
			tintColor: UIColor(white: 1, alpha: CGFloat(max(0, min(0.25, blurAmount * 0.004)))),
			saturationDeltaFactor: CGFloat(max(1, min(2.8, blurAmount * (IS_IPAD ? 0.035 : 0.045)))),
			maskImage: nil
		)
	}

	@objc
	func updateImage() {
		DispatchQueue.global(qos: .userInteractive).async {
			let tmp = self.blurImage(self.blurAmount)
			DispatchQueue.main.async {
				self.imageView.image = tmp
			}
		}
	}

	func updateImageDebounced() {
		performSelector(inBackground: #selector(updateImage), with: IS_IPAD ? 0.1 : 0.06)
	}

	@objc
	func sliderChanged(_ sender: UISlider) {
		blurAmount = sender.value
		updateImageDebounced()
		delayedAction?.action {
			self.updateImage()
		}
	}

	@objc
	func saveImage(_ button: UIBarButtonItem) {
		button.isEnabled = false

		PHPhotoLibrary.save(image: imageView.image!, toAlbum: "Blear") { result in
			button.isEnabled = true

			let HUD = JGProgressHUD(style: .dark)
			HUD.indicatorView = JGProgressHUDSuccessIndicatorView()
			HUD.animation = JGProgressHUDFadeZoomAnimation()
			HUD.vibrancyEnabled = true
			HUD.contentInsets = UIEdgeInsets(all: 30)

			if case .failure(let error) = result {
				HUD.indicatorView = JGProgressHUDErrorIndicatorView()
				HUD.textLabel.text = error.localizedDescription
				HUD.show(in: self.view)
				HUD.dismiss(afterDelay: 3)
				return
			}

			//HUD.indicatorView = JGProgressHUDImageIndicatorView(image: #imageLiteral(resourceName: "HudSaved"))
			HUD.show(in: self.view)
			HUD.dismiss(afterDelay: 0.8)

			// Only on first save
			if UserDefaults.standard.isFirstLaunch {
				delay(seconds: 1) {
					let alert = UIAlertController(
						title: "Changing Wallpaper",
						message: "In the Photos app go to the wallpaper you just saved, tap the action button on the bottom left and choose 'Use as Wallpaper'.",
						preferredStyle: .alert
					)
					alert.addAction(UIAlertAction(title: "OK", style: .default))
					self.present(alert, animated: true)
				}
			}
		}
	}

	/// TODO: Improve this method
	func changeImage(_ image: UIImage) {
		let tmp = NSKeyedUnarchiver.unarchiveObject(with: NSKeyedArchiver.archivedData(withRootObject: imageView)) as! UIImageView
		view.insertSubview(tmp, aboveSubview: imageView)
		imageView.image = image
		sourceImage = imageView.toImage()
		updateImageDebounced()

		// The delay here is important so it has time to blur the image before we start fading
		UIView.animate(
			withDuration: 0.6,
			delay: 0.3,
			options: .curveEaseInOut,
			animations: {
				tmp.alpha = 0
			}, completion: { _ in
				tmp.removeFromSuperview()
			}
		)
	}

	func randomImage() {
		changeImage(UIImage(contentsOf: randomImageIterator.next()!)!)
	}
}
