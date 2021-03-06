require 'mimemagic'

module Skydrive
  class File
    attr_accessor :uri, :file_size, :name, :server_relative_url, :time_created, :time_last_modified, :title, :content_tag,
                  :content_type, :is_image, :is_text, :is_video, :mime_comment, :icon, :kind, :suffix, :is_embeddable,
                  :homework_submission_url

    def update_content_type_data(allowed_extensions=nil)
      self.is_embeddable = true
      mm = MimeMagic.by_path(self.name)
      if mm
        if mm.image?
          case mm.to_s
            when 'image/png'
              self.icon = "/assets/skydrive/icon-png.png"
            when 'image/jpeg'
              self.icon = "/assets/skydrive/icon-jpg.png"
            else
              self.icon = "/assets/skydrive/icon-jpg.png"
          end
        elsif mm.text? || mm.subtype == "msword"
          if mm.extensions & ['doc', 'docx']
            self.icon = "/assets/skydrive/icon-word.png"
          else
            self.icon = "/assets/skydrive/icon-file.png"
          end
        elsif mm.to_s == 'application/pdf'
          self.icon = "/assets/skydrive/icon-pdf.png"
        else
          self.icon = "/assets/skydrive/icon-file.png"
        end
        self.kind = mm.comment
        self.suffix = mm.extensions.last

        if !allowed_extensions || (allowed_extensions & mm.extensions).size > 0
          self.is_embeddable = true
        else
          self.is_embeddable = false
        end
      else
        self.icon = "/assets/skydrive/icon-file.png"
        self.kind = ''
        self.suffix = self.name.split('.').try(:last) || ''
        self.is_embeddable = false
      end
    end
  end
end
