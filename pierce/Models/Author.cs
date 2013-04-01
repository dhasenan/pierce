using System;

namespace pierce
{
    public class Author
    {
        public string Name;
        public Uri Link;
        public string Email;

        public override bool Equals(object obj)
        {
            if (obj == null)
                return false;
            if (ReferenceEquals(this, obj))
                return true;
            if (obj.GetType() != typeof(Author))
                return false;
            Author other = (Author)obj;
            return Name == other.Name;
        }
        

        public override int GetHashCode()
        {
            unchecked
            {
                return (Name != null ? Name.GetHashCode() : 0);
            }
        }
    }
}

