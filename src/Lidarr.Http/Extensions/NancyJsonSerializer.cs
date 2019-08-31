﻿using System.Collections.Generic;
using System.IO;
using Nancy;
using Nancy.Responses.Negotiation;
using NzbDrone.Common.Serializer;

namespace Lidarr.Http.Extensions
{
    public class NancyJsonSerializer : ISerializer
    {
        public bool CanSerialize(MediaRange contentType)
        {
            return true;
        }

        public void Serialize<TModel>(MediaRange contentType, TModel model, Stream outputStream)
        {
            Json.Serialize(model, outputStream);
        }

        public IEnumerable<string> Extensions { get; private set; }
    }
}
