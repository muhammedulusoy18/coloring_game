import 'package:image/image.dart' as img;

void main() {
  final image = img.Image(width: 10, height: 10);
  image.addFrame(img.Image(width: 10, height: 10));
  
  final bytes = img.encodeGif(image);
  print(bytes.length);
}
